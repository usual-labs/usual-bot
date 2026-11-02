import Foundation

/// A binary WebSocket: the screen's RFB stream (`/api/display/ws`). `URLSessionWebSocketTask` in
/// the app; an in-memory script in tests.
public protocol ScreenSocket: Sendable {
    func send(_ data: Data) async throws
    /// The next binary frame. Throws `ScreenSocketClosed` once the socket is closed.
    func receive() async throws -> Data
    /// Closes with 1000, which the gateway reads as "the viewer closed the window".
    func close()
}

/// The screen socket closed. `code` is the WebSocket close code, when the server sent one:
/// 4000 someone else took control, 4001 the screen stopped, 4401 the ticket was spent or stale.
public struct ScreenSocketClosed: Error, Equatable, Sendable {
    public let code: Int?
    public let reason: String
}

final class URLSessionScreenSocket: ScreenSocket, @unchecked Sendable {
    // @unchecked: URLSessionWebSocketTask is safe to use from any thread.
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = 32 * 1024 * 1024
        task.resume()
    }

    func send(_ data: Data) async throws {
        try await task.send(.data(data))
    }

    func receive() async throws -> Data {
        do {
            switch try await task.receive() {
            case .data(let data): return data
            case .string(let text): return Data(text.utf8)
            @unknown default: throw GatewayError.invalidResponse
            }
        } catch {
            let code = task.closeCode == .invalid ? nil : task.closeCode.rawValue
            let reason = task.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? ""
            throw ScreenSocketClosed(code: code, reason: reason)
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// A VNC viewer's side of RFB 3.8 (RFC 6143), as much as a Hermes screen needs: no security
/// (Xvnc runs `-SecurityTypes None` behind the gateway's ticket), 32-bit pixels, and the Raw,
/// CopyRect and ZRLE encodings plus DesktopSize. Input goes out as key and pointer events; the
/// gateway drops them unless this viewer holds the lease.
actor RFBClient {
    enum Failure: Error, Equatable {
        case notRFB
        case refused(String)
        case noUsableSecurity
        case unexpected(String)
    }

    /// What this app asks for, best first. ZRLE keeps a full repaint small enough for a phone.
    static let encodings: [Int32] = [16, 1, 0, -223]

    private let socket: any ScreenSocket
    private var buffer: [UInt8] = []
    private var offset = 0
    private var framebuffer = Framebuffer(width: 0, height: 0)
    private var zrle = ZRLEDecoder()
    private var needsFullUpdate = true
    private(set) var name = ""

    init(socket: any ScreenSocket) {
        self.socket = socket
    }

    /// Version, security and init. Returns the screen as it starts, before its first update.
    func handshake() async throws -> Framebuffer {
        let banner = String(decoding: try await read(12), as: UTF8.self)
        guard banner.hasPrefix("RFB 003."), let minor = Int(banner.dropFirst(8).prefix(3)) else { throw Failure.notRFB }
        let version = minor >= 8 ? 8 : minor >= 7 ? 7 : 3
        try await send(Array("RFB 003.00\(version)\n".utf8))
        if version >= 7 {
            let count = Int(try await u8())
            guard count > 0 else { throw Failure.refused(try await reasonString()) }
            let types = try await read(count)
            guard types.contains(1) else { throw Failure.noUsableSecurity }
            try await send([1])
            if version >= 8, try await u32() != 0 { throw Failure.refused(try await reasonString()) }
        } else {
            switch try await u32() {
            case 0: throw Failure.refused(try await reasonString())
            case 1: break
            default: throw Failure.noUsableSecurity
            }
        }
        try await send([1])  // ClientInit: shared, so the agent's own view stays connected
        let width = Int(try await u16())
        let height = Int(try await u16())
        _ = try await read(16)  // the server's pixel format; this app sets its own next
        let nameLength = Int(try await u32())
        name = String(decoding: try await read(min(nameLength, 4096)), as: UTF8.self)
        if nameLength > 4096 { _ = try await read(nameLength - 4096) }
        framebuffer = Framebuffer(width: width, height: height)
        try await send(Self.setPixelFormat)
        try await send(Self.setEncodings(Self.encodings))
        try await requestUpdate()
        return framebuffer
    }

    /// Reads until the next screen update has been applied, asks for the one after, and returns
    /// the screen.
    func nextFrame() async throws -> Framebuffer {
        while true {
            switch try await u8() {
            case 0:
                _ = try await read(1)
                let rectangles = Int(try await u16())
                for _ in 0..<rectangles { try await readRectangle() }
                try await requestUpdate()
                return framebuffer
            case 1:  // colour map entries: unused with true colour
                _ = try await read(1)
                _ = try await u16()
                let count = Int(try await u16())
                _ = try await read(count * 6)
            case 2:  // bell
                break
            case 3:  // the server's clipboard; Hermes turns it off, so skip it
                _ = try await read(3)
                let length = Int(try await u32())
                guard length <= 1 << 20 else { throw Failure.unexpected("clipboard too large") }
                _ = try await read(length)
            case let other:
                throw Failure.unexpected("server message \(other)")
            }
        }
    }

    func pointer(x: Int, y: Int, buttons: UInt8) async throws {
        try await send(Self.pointerEvent(x: x, y: y, buttons: buttons))
    }

    func key(_ keysym: UInt32, down: Bool) async throws {
        try await send(Self.keyEvent(keysym, down: down))
    }

    private func readRectangle() async throws {
        let x = Int(try await u16())
        let y = Int(try await u16())
        let width = Int(try await u16())
        let height = Int(try await u16())
        let encoding = Int32(bitPattern: try await u32())
        switch encoding {
        case 0:
            framebuffer.putRaw(x: x, y: y, width: width, height: height, bytes: try await read(width * height * 4))
        case 1:
            let sx = Int(try await u16())
            let sy = Int(try await u16())
            framebuffer.copy(fromX: sx, fromY: sy, toX: x, toY: y, width: width, height: height)
        case 16:
            let length = Int(try await u32())
            let compressed = Array(try await read(length))
            try zrle.decode(compressed, x: x, y: y, width: width, height: height, into: &framebuffer)
        case -223:
            framebuffer.resize(width: width, height: height)
            needsFullUpdate = true
        default:
            throw Failure.unexpected("encoding \(encoding)")
        }
    }

    private func requestUpdate() async throws {
        let incremental = !needsFullUpdate
        needsFullUpdate = false
        try await send(
            Self.updateRequest(incremental: incremental, width: framebuffer.width, height: framebuffer.height))
    }

    // MARK: - Messages

    /// SetPixelFormat: 32 bits per pixel, depth 24, little-endian true colour, red at bit 16,
    /// green at 8, blue at 0. In memory: blue, green, red, unused, as `Framebuffer` keeps it.
    static let setPixelFormat: [UInt8] = [0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0]

    static func setEncodings(_ encodings: [Int32]) -> [UInt8] {
        [2, 0] + be16(encodings.count) + encodings.flatMap { be32(UInt32(bitPattern: $0)) }
    }

    static func updateRequest(incremental: Bool, width: Int, height: Int) -> [UInt8] {
        [3, incremental ? 1 : 0] + be16(0) + be16(0) + be16(width) + be16(height)
    }

    static func pointerEvent(x: Int, y: Int, buttons: UInt8) -> [UInt8] {
        [5, buttons] + be16(max(x, 0)) + be16(max(y, 0))
    }

    static func keyEvent(_ keysym: UInt32, down: Bool) -> [UInt8] {
        [4, down ? 1 : 0, 0, 0] + be32(keysym)
    }

    private static func be16(_ value: Int) -> [UInt8] {
        let clamped = UInt16(clamping: value)
        return [UInt8(clamped >> 8), UInt8(clamped & 0xFF)]
    }

    private static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    // MARK: - Reading

    private func send(_ bytes: [UInt8]) async throws {
        try await socket.send(Data(bytes))
    }

    /// Exactly `count` bytes, however the server split them into frames.
    private func read(_ count: Int) async throws -> ArraySlice<UInt8> {
        if offset > 1 << 20 || offset == buffer.count {
            buffer.removeFirst(offset)
            offset = 0
        }
        while buffer.count - offset < count {
            buffer.append(contentsOf: try await socket.receive())
        }
        defer { offset += count }
        return buffer[offset..<offset + count]
    }

    private func u8() async throws -> UInt8 { try await read(1).first! }

    private func u16() async throws -> UInt16 {
        let bytes = try await read(2)
        return UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.startIndex + 1])
    }

    private func u32() async throws -> UInt32 {
        try await read(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private func reasonString() async throws -> String {
        let length = Int(try await u32())
        return String(decoding: try await read(min(length, 4096)), as: UTF8.self)
    }
}
