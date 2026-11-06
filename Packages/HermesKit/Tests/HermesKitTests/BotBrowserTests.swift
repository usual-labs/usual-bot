import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import HermesKit

@MainActor
struct BotBrowserTests {
    private final class Sockets: Sendable {
        let opened = Mutex<[(URL, ScriptedScreenSocket)]>([])
        var all: [(URL, ScriptedScreenSocket)] { opened.withLock { $0 } }
    }

    /// A browser whose gateway answers the plugin's routes from `status` and mints tickets t1, t2, ….
    private func make(status: (Int, String) = (200, #"{"bot":"scout","available":true,"browser":true}"#))
        -> (BotBrowser, ScriptedHTTP, Sockets)
    {
        let tickets = Mutex(0)
        let http = ScriptedHTTP { request in
            if request.url?.path() == "/api/auth/ws-ticket" {
                let next = tickets.withLock { count in
                    count += 1
                    return count
                }
                return (200, #"{"ticket":"t\#(next)"}"#)
            }
            return status
        }
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        let sockets = Sockets()
        let browser = BotBrowser(
            profile: "scout", auth: { auth },
            makeSocket: { url in
                let socket = ScriptedScreenSocket()
                sockets.opened.withLock { $0.append((url, socket)) }
                return socket
            })
        return (browser, http, sockets)
    }

    private func socket(_ sockets: Sockets, _ index: Int = 0) async throws -> ScriptedScreenSocket {
        try await waitUntilOnMain { sockets.all.count > index }
        return sockets.all[index].1
    }

    private static func text(_ json: String) -> [UInt8] { Array(json.utf8) }

    /// A 3×2 PNG, as the feed sends a frame.
    private static func png() -> [UInt8] {
        let context = CGContext(
            data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return Array(data as Data)
    }

    @Test func statusSaysWhetherTheBotHasABrowserToWatch() async throws {
        let (browser, http, _) = make()
        await browser.refresh()
        #expect(browser.isAvailable)
        #expect(
            http.requests.last?.url?.absoluteString
                == "http://100.101.102.103:9119/api/plugins/usual-browser/status?bot=scout")
        #expect(http.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer a0")

        let (headed, _, _) = make(status: (200, #"{"bot":"scout","available":false,"browser":false}"#))
        await headed.refresh()
        #expect(!headed.isAvailable)
    }

    @Test func aGatewayWithoutThePluginHasNoBrowser() async throws {
        let (browser, _, _) = make(status: (404, #"{"detail":"Not Found"}"#))
        await browser.refresh()
        #expect(!browser.isAvailable)
    }

    @Test func watchingShowsFramesAndTheTab() async throws {
        let (browser, _, sockets) = make()
        browser.connect()
        let socket = try await socket(sockets)
        #expect(
            sockets.all[0].0.absoluteString
                == "ws://100.101.102.103:9119/api/plugins/usual-browser/feed?bot=scout&ticket=t1")

        socket.deliver(Self.text(#"{"type": "state", "state": "live"}"#), frame: .max)
        socket.deliver(Self.text(#"{"type": "tab", "url": "https://example.com/", "title": "Example"}"#), frame: .max)
        socket.deliver(Self.png(), frame: .max)
        try await waitUntilOnMain { browser.frame != nil }
        #expect(browser.connection == .live)
        #expect(browser.frameSize == CGSize(width: 3, height: 2))
        #expect(browser.page == BotBrowser.Page(url: "https://example.com/", title: "Example"))

        // The Bot closed its browser: nothing to show until it browses again.
        socket.deliver(Self.text(#"{"type": "state", "state": "waiting"}"#), frame: .max)
        try await waitUntilOnMain { browser.connection == .waiting }
        #expect(browser.frame == nil)
        #expect(browser.page == nil)

        browser.disconnect()
        #expect(socket.closedByClient)
        #expect(browser.connection == .idle)
    }

    @Test func aStaleTicketTriesAgainWithAFreshOne() async throws {
        let (browser, _, sockets) = make()
        browser.connect()
        try await socket(sockets, 0).serverClose(4401)
        let second = try await socket(sockets, 1)
        #expect(sockets.all[1].0.query()?.contains("ticket=t2") == true)
        second.deliver(Self.text(#"{"type": "state", "state": "waiting"}"#), frame: .max)
        try await waitUntilOnMain { browser.connection == .waiting }
    }

    @Test func aLostFeedSaysSo() async throws {
        let (browser, _, sockets) = make()
        browser.connect()
        try await socket(sockets).serverClose(1011)
        try await waitUntilOnMain { browser.connection == .failed("Lost the connection to the browser.") }
    }

    @Test func framesAndMessagesAreToldApartByTheirFirstByte() {
        #expect(BotBrowser.isText(Data(#"{"type":"tab"}"#.utf8)))
        #expect(!BotBrowser.isText(Data(Self.png())))
        #expect(!BotBrowser.isText(Data([0xFF, 0xD8, 0xFF])))  // JPEG
    }

    @Test func onlyABrowserToolCountsAsUsingTheBrowser() {
        func event(_ type: String, _ payload: JSONValue = [:]) -> GatewayEvent {
            GatewayEvent(type: type, sessionID: "live-1", seq: nil, payload: payload)
        }
        func state(_ name: String) -> ThreadState {
            var state = ThreadState()
            state.sendLocally("Look it up")
            state.apply(event("message.start"))
            state.apply(event("tool.start", ["tool_id": "t1", "name": .string(name)]))
            return state
        }
        #expect(state("browser_navigate").isUsingBrowser)
        #expect(!state("computer_use").isUsingBrowser)
    }
}
