import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// The server's end of a screen socket: bytes queued for the client, in frames of any size, and
/// what the client sent.
final class ScriptedScreenSocket: ScreenSocket {
    private struct Inbox {
        var queue: [Data] = []
        var waiter: CheckedContinuation<Data?, Never>?
        var closeCode: Int?
    }

    private let inbox = Mutex(Inbox())
    private let outbound = Mutex<[[UInt8]]>([])

    var sent: [[UInt8]] { outbound.withLock { $0 } }
    var closedByClient: Bool { inbox.withLock { $0.closeCode == 1000 } }

    /// Queues `bytes`, split into frames of `frame` bytes so reads must span them.
    func deliver(_ bytes: [UInt8], frame: Int = 5) {
        for start in stride(from: 0, to: bytes.count, by: frame) {
            let piece = Data(bytes[start..<min(start + frame, bytes.count)])
            let waiter = inbox.withLock { inbox -> CheckedContinuation<Data?, Never>? in
                if let waiter = inbox.waiter {
                    inbox.waiter = nil
                    return waiter
                }
                inbox.queue.append(piece)
                return nil
            }
            waiter?.resume(returning: piece)
        }
    }

    /// The server closes with `code`.
    func serverClose(_ code: Int) {
        finish(code)
    }

    func send(_ data: Data) async throws { outbound.withLock { $0.append(Array(data)) } }

    func receive() async throws -> Data {
        let data: Data? = await withCheckedContinuation { continuation in
            let immediate = inbox.withLock { inbox -> Data?? in
                if !inbox.queue.isEmpty { return .some(inbox.queue.removeFirst()) }
                if inbox.closeCode != nil { return .some(nil) }
                inbox.waiter = continuation
                return nil
            }
            if let immediate { continuation.resume(returning: immediate) }
        }
        guard let data else {
            throw ScreenSocketClosed(code: inbox.withLock { $0.closeCode }, reason: "")
        }
        return data
    }

    func close() { finish(1000) }

    private func finish(_ code: Int) {
        let waiter = inbox.withLock { inbox -> CheckedContinuation<Data?, Never>? in
            if inbox.closeCode == nil { inbox.closeCode = code }
            defer { inbox.waiter = nil }
            return inbox.waiter
        }
        waiter?.resume(returning: nil)
    }
}

/// Bytes a server sends.
enum RFBServer {
    static func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    static func be32(_ value: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8(value >> $0 & 0xFF) } }

    /// Version 3.8, security "None", the security result, and ServerInit for a `width`×`height` screen.
    static func greeting(width: Int, height: Int, name: String = "bot") -> [UInt8] {
        Array("RFB 003.008\n".utf8) + [1, 1] + be32(0) + be16(width) + be16(height)
            + [32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0] + be32(name.utf8.count) + Array(name.utf8)
    }

    static func update(_ rectangles: [[UInt8]]) -> [UInt8] {
        [0, 0] + be16(rectangles.count) + rectangles.flatMap { $0 }
    }

    static func rectangle(x: Int, y: Int, width: Int, height: Int, encoding: Int32, body: [UInt8]) -> [UInt8] {
        be16(x) + be16(y) + be16(width) + be16(height) + be32(Int(UInt32(bitPattern: encoding))) + body
    }

    /// `data` as stored deflate blocks after a zlib header: valid zlib with no compression.
    static func storedZlib(_ data: [UInt8], header: Bool) -> [UInt8] {
        let length = data.count
        return (header ? [0x78, 0x01] : []) + [0, UInt8(length & 0xFF), UInt8(length >> 8)]
            + [UInt8(~length & 0xFF), UInt8((~length >> 8) & 0xFF)] + data
    }
}

struct RFBClientTests {
    @Test func handshakesAndAsksForPixelsItCanDraw() async throws {
        let socket = ScriptedScreenSocket()
        socket.deliver(RFBServer.greeting(width: 4, height: 2))
        let client = RFBClient(socket: socket)
        let start = try await client.handshake()

        #expect(start.width == 4 && start.height == 2)
        let sent = socket.sent
        #expect(sent[0] == Array("RFB 003.008\n".utf8))
        #expect(sent[1] == [1])  // security: None
        #expect(sent[2] == [1])  // ClientInit: shared
        #expect(sent[3] == RFBClient.setPixelFormat)
        #expect(sent[4] == [2, 0, 0, 4, 0, 0, 0, 16, 0, 0, 0, 1, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0x21])
        #expect(sent[5] == [3, 0, 0, 0, 0, 0, 0, 4, 0, 2])  // a full first update
    }

    @Test func drawsRawAndCopyRectThenAsksForChangesOnly() async throws {
        let socket = ScriptedScreenSocket()
        socket.deliver(RFBServer.greeting(width: 4, height: 2))
        let client = RFBClient(socket: socket)
        _ = try await client.handshake()
        socket.deliver(
            RFBServer.update([
                RFBServer.rectangle(x: 0, y: 0, width: 2, height: 1, encoding: 0, body: [1, 2, 3, 0, 4, 5, 6, 0]),
                RFBServer.rectangle(
                    x: 2, y: 1, width: 2, height: 1, encoding: 1, body: RFBServer.be16(0) + RFBServer.be16(0)),
            ]), frame: 3)
        let frame = try await client.nextFrame()

        #expect(frame.pixel(x: 0, y: 0) == [1, 2, 3])
        #expect(frame.pixel(x: 1, y: 0) == [4, 5, 6])
        #expect(frame.pixel(x: 2, y: 1) == [1, 2, 3])
        #expect(frame.pixel(x: 3, y: 1) == [4, 5, 6])
        #expect(frame.pixel(x: 3, y: 0) == [0, 0, 0])
        #expect(socket.sent.last == [3, 1, 0, 0, 0, 0, 0, 4, 0, 2])
        #expect(frame.image()?.width == 4)
    }

    @Test func zrleTilesShareOneStreamAcrossRectangles() async throws {
        let socket = ScriptedScreenSocket()
        socket.deliver(RFBServer.greeting(width: 70, height: 4))
        let client = RFBClient(socket: socket)
        _ = try await client.handshake()
        // Rect 1, 4×2: packed palette of two colours, 1 bit per pixel, rows padded to a byte.
        let palette: [UInt8] = [2, 9, 9, 9, 7, 7, 7, 0b0101_0000, 0b1010_0000]
        // Rect 2, 3×2: palette RLE (two colours): colour 1 for a run of 4, then colour 0 twice.
        let paletteRLE: [UInt8] = [130, 1, 1, 1, 2, 2, 2, 0x81, 3, 0x00, 0x00]
        socket.deliver(
            RFBServer.update([
                RFBServer.rectangle(
                    x: 0, y: 0, width: 4, height: 2, encoding: 16,
                    body: RFBServer.be32(palette.count + 7) + RFBServer.storedZlib(palette, header: true)),
                RFBServer.rectangle(
                    x: 0, y: 2, width: 3, height: 2, encoding: 16,
                    body: RFBServer.be32(paletteRLE.count + 5) + RFBServer.storedZlib(paletteRLE, header: false)),
            ]))
        let frame = try await client.nextFrame()

        #expect((0..<4).map { frame.pixel(x: $0, y: 0) } == [[9, 9, 9], [7, 7, 7], [9, 9, 9], [7, 7, 7]])
        #expect((0..<4).map { frame.pixel(x: $0, y: 1) } == [[7, 7, 7], [9, 9, 9], [7, 7, 7], [9, 9, 9]])
        #expect((0..<3).map { frame.pixel(x: $0, y: 2) } == [[2, 2, 2], [2, 2, 2], [2, 2, 2]])
        #expect((0..<3).map { frame.pixel(x: $0, y: 3) } == [[2, 2, 2], [1, 1, 1], [1, 1, 1]])
    }

    /// Bytes from Python's zlib with a sync flush after each rectangle, as Xvnc sends them.
    @Test func zrleInflatesRealCompressedData() async throws {
        let first: [UInt8] = [0x78, 0x9c, 0x62, 0xe4, 0x12, 0x91, 0x03, 0x00, 0x00, 0x00, 0xff, 0xff]
        let second: [UInt8] = [
            0x6a, 0x60, 0x64, 0x62, 0xb6, 0x67, 0x60, 0x60, 0x64, 0x02, 0xd2, 0x4c, 0xcc, 0x2c, 0xcc, 0x2c, 0xac,
            0x2c, 0xac, 0x6c, 0xac, 0x6c, 0xec, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff,
        ]
        let socket = ScriptedScreenSocket()
        socket.deliver(RFBServer.greeting(width: 70, height: 3))
        let client = RFBClient(socket: socket)
        _ = try await client.handshake()
        socket.deliver(
            RFBServer.update([
                // Solid (10, 20, 30).
                RFBServer.rectangle(
                    x: 0, y: 0, width: 2, height: 2, encoding: 16, body: RFBServer.be32(first.count) + first),
                // Two tiles: a plain run of 64 × (1, 2, 3), then 6 raw pixels.
                RFBServer.rectangle(
                    x: 0, y: 2, width: 70, height: 1, encoding: 16, body: RFBServer.be32(second.count) + second),
            ]), frame: 7)
        let frame = try await client.nextFrame()

        #expect(frame.pixel(x: 1, y: 1) == [10, 20, 30])
        #expect(frame.pixel(x: 0, y: 2) == [1, 2, 3])
        #expect(frame.pixel(x: 63, y: 2) == [1, 2, 3])
        #expect(frame.pixel(x: 64, y: 2) == [0, 1, 2])
        #expect(frame.pixel(x: 69, y: 2) == [5, 6, 7])
    }

    @Test func aResizeAsksForTheWholeScreenAgain() async throws {
        let socket = ScriptedScreenSocket()
        socket.deliver(RFBServer.greeting(width: 4, height: 2))
        let client = RFBClient(socket: socket)
        _ = try await client.handshake()
        socket.deliver(
            RFBServer.update([RFBServer.rectangle(x: 0, y: 0, width: 8, height: 6, encoding: -223, body: [])]))
        let frame = try await client.nextFrame()

        #expect(frame.width == 8 && frame.height == 6)
        #expect(socket.sent.last == [3, 0, 0, 0, 0, 0, 0, 8, 0, 6])
    }

    @Test func aRefusalSaysWhy() async throws {
        let socket = ScriptedScreenSocket()
        let reason = Array("Too many viewers".utf8)
        socket.deliver(Array("RFB 003.008\n".utf8) + [0] + RFBServer.be32(reason.count) + reason)
        await #expect(throws: RFBClient.Failure.refused("Too many viewers")) {
            _ = try await RFBClient(socket: socket).handshake()
        }
    }

    @Test func inputMessagesMatchTheGatewaysFilter() {
        // tools/bot_desktop/rfb_filter.py frames PointerEvent as 6 bytes and KeyEvent as 8.
        #expect(RFBClient.pointerEvent(x: 300, y: 2, buttons: 1) == [5, 1, 1, 44, 0, 2])
        #expect(RFBClient.keyEvent(Keysym.returnKey.value, down: true) == [4, 1, 0, 0, 0, 0, 0xFF, 0x0D])
    }

    @Test func charactersBecomeKeysyms() {
        #expect(Keysym(character: "a")?.value == 0x61)
        #expect(Keysym(character: "é")?.value == 0xE9)
        #expect(Keysym(character: "€")?.value == 0x0100_20AC)
        #expect(Keysym(character: "\n") == .returnKey)
        #expect(Keysym(character: "\u{1}") == nil)
        #expect(Keysym.function(1).value == 0xFFBE)
    }
}
