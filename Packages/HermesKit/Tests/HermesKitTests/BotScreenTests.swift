import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// Shaped like `tui_gateway/contracts/display.py`'s `DisplayObserveResult`.
private func observed(viewer: String, ticket: String = "t1", lease: JSONValue = ["holder": "agent", "epoch": 1])
    -> JSONValue
{
    [
        "ticket": .string(ticket), "path": "/api/display/ws", "viewer_id": .string(viewer), "profile": "scout",
        "supported": true, "installed": true, "missing": [], "running": true, "geometry": "1440x900",
        "placement": "terminal:docker", "lease": lease, "profile_key": "home-scout",
    ]
}

private func lease(_ holder: String, hash: String? = nil, epoch: Int) -> JSONValue {
    [
        "holder": .string(holder), "viewer_id": .null, "viewer_hash": hash.map(JSONValue.string) ?? .null,
        "since": 1, "epoch": .number(Double(epoch)), "reason": "",
    ]
}

@MainActor
struct BotScreenTests {
    private final class Sockets: Sendable {
        let opened = Mutex<[(URL, ScriptedScreenSocket)]>([])
        var all: [(URL, ScriptedScreenSocket)] { opened.withLock { $0 } }
    }

    private func make() async -> (BotScreen, ScriptedGateway, Sockets) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let sockets = Sockets()
        let screen = BotScreen(
            profile: "scout", channel: { channel }, gateway: { testGateway },
            makeSocket: { url in
                let socket = ScriptedScreenSocket()
                socket.deliver(RFBServer.greeting(width: 4, height: 2))
                socket.deliver(RFBServer.update([]))
                sockets.opened.withLock { $0.append((url, socket)) }
                return socket
            })
        return (screen, gateway, sockets)
    }

    @Test func watchingRedeemsTheTicketOnItsOwnSocket() async throws {
        let (screen, gateway, sockets) = await make()
        screen.connect()
        let params = try await gateway.answer(0, method: "display.observe", result: observed(viewer: "v1"))
        try await waitUntilOnMain { screen.connection == .live }

        #expect(params == ["profile": "scout"])
        let url = try #require(sockets.all.first?.0)
        #expect(url.absoluteString == "ws://100.101.102.103:9119/api/display/ws?display_ticket=t1")
        #expect(screen.frameSize == CGSize(width: 4, height: 2))
        #expect(screen.hasScreen)
        #expect(screen.control == .agent)
    }

    @Test func takeOverNamesThisViewerAndHandBackReturnsControl() async throws {
        let (screen, gateway, _) = await make()
        screen.connect()
        _ = try await gateway.answer(0, method: "display.observe", result: observed(viewer: "v1"))
        try await waitUntilOnMain { screen.connection == .live }

        async let took: Void = screen.takeOver()
        let acquire = try await gateway.answer(
            1, method: "display.lease.acquire", result: ["lease": lease("human", hash: BotScreen.hash("v1"), epoch: 2)])
        await took
        #expect(acquire == ["profile": "scout", "viewer_id": "v1"])
        #expect(screen.control == .you)

        async let gave: Void = screen.handBack()
        let release = try await gateway.answer(
            2, method: "display.lease.release", result: ["lease": lease("agent", epoch: 3)])
        await gave
        #expect(release == ["profile": "scout", "viewer_id": "v1"])
        #expect(screen.control == .agent)
    }

    @Test func leaseEventsForThisProfileWinOnlyWhenNewer() async throws {
        let (screen, gateway, _) = await make()
        screen.connect()
        _ = try await gateway.answer(0, method: "display.observe", result: observed(viewer: "v1"))
        try await waitUntilOnMain { screen.connection == .live }

        func event(_ key: String, _ value: JSONValue) -> GatewayEvent {
            GatewayEvent(
                type: "display.lease", sessionID: "", seq: nil, payload: ["profile_key": .string(key), "lease": value])
        }
        screen.apply(event("home-other", lease("human", hash: "abc", epoch: 5)))
        #expect(screen.control == .agent)
        screen.apply(event("home-scout", lease("human", hash: "abc", epoch: 5)))
        #expect(screen.control == .someoneElse)
        screen.apply(event("home-scout", lease("agent", epoch: 4)))
        #expect(screen.control == .someoneElse)
    }

    @Test func losingControlToSomeoneElseWatchesAgainWithTheSameViewer() async throws {
        let (screen, gateway, sockets) = await make()
        screen.connect()
        _ = try await gateway.answer(0, method: "display.observe", result: observed(viewer: "v1"))
        try await waitUntilOnMain { screen.connection == .live }

        sockets.all[0].1.serverClose(4000)
        let again = try await gateway.answer(1, method: "display.observe", result: observed(viewer: "v1", ticket: "t2"))
        try await waitUntilOnMain { sockets.all.count == 2 && screen.connection == .live }

        #expect(again == ["profile": "scout", "viewer_id": "v1"])
        #expect(screen.notice != nil)
    }

    @Test func aNewViewerKeepsControlTheOldOneHad() async throws {
        let (screen, gateway, _) = await make()
        screen.connect()
        _ = try await gateway.answer(0, method: "display.observe", result: observed(viewer: "v1"))
        try await waitUntilOnMain { screen.connection == .live }

        // The app's socket reconnected, so the gateway mints a new viewer; the lease still names the old one.
        screen.linkChanged()
        _ = try await gateway.answer(
            1, method: "display.observe",
            result: observed(viewer: "v2", lease: lease("human", hash: BotScreen.hash("v1"), epoch: 2)))
        let acquire = try await gateway.answer(
            2, method: "display.lease.acquire", result: ["lease": lease("human", hash: BotScreen.hash("v2"), epoch: 3)])
        try await waitUntilOnMain { screen.connection == .live }

        #expect(acquire == ["profile": "scout", "viewer_id": "v2"])
        #expect(screen.control == .you)
    }

    @Test func aStoppedScreenEndsTheViewAndClosingSaysSo() async throws {
        let (screen, gateway, sockets) = await make()
        screen.connect()
        _ = try await gateway.answer(0, method: "display.observe", result: observed(viewer: "v1"))
        try await waitUntilOnMain { screen.connection == .live }

        sockets.all[0].1.serverClose(4001)
        try await waitUntilOnMain { screen.connection == .idle }
        var stopped = observed(viewer: "v1")
        if case .object(var fields) = stopped {
            fields["running"] = false
            stopped = .object(fields)
        }
        _ = try await gateway.answer(1, method: "display.status", result: stopped)
        try await waitUntilOnMain { screen.status?.running == false }

        screen.connect()
        _ = try await gateway.answer(2, method: "display.observe", result: observed(viewer: "v1"))
        try await waitUntilOnMain { screen.connection == .live }
        screen.disconnect()
        #expect(sockets.all[1].1.closedByClient)
    }

    @Test func aGatewayWithoutScreensHidesTheWayIn() async throws {
        let (screen, gateway, _) = await make()
        async let refreshed: Void = screen.refresh()
        _ = try await gateway.answer(0, method: "display.status", error: (-32601, "method not found"))
        await refreshed
        #expect(screen.status != nil)
        #expect(!screen.hasScreen)
    }
}
