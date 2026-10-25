import Foundation
import Testing

@testable import HermesKit

struct JSONRPCChannelTests {
    private func makeChannel() async -> (JSONRPCChannel, FakeSocket) {
        let socket = FakeSocket()
        let channel = JSONRPCChannel(socket: socket)
        await channel.start()
        return (channel, socket)
    }

    @Test func readyReportsTheDialect() async throws {
        let (channel, socket) = await makeChannel()
        socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"replay_epoch":"e1","session_authority":true}}}"#
        )
        let ready = try await channel.waitUntilReady()
        #expect(ready == GatewayReady(dialect: .canonical, replayEpoch: "e1"))
    }

    @Test func readyWithoutAuthorityIsLegacy() async throws {
        let (channel, socket) = await makeChannel()
        socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"replay_epoch":3}}}"#)
        #expect(try await channel.waitUntilReady().dialect == .legacy)
    }

    @Test func callMatchesReplyByID() async throws {
        let (channel, socket) = await makeChannel()
        async let result = channel.call("profiles.list", params: ["include_sessions": true])
        try await waitUntil { socket.sent.count == 1 }

        let request = socket.sent[0]
        #expect(request["method"] == "profiles.list")
        #expect(request["params"] == ["include_sessions": true])
        #expect(request["jsonrpc"] == "2.0")
        let id = try #require(request["id"]?.intValue)
        socket.deliver(#"{"jsonrpc":"2.0","id":\#(id),"result":{"profiles":[]}}"#)

        #expect(try await result == ["profiles": .array([])])
    }

    @Test func rpcErrorThrows() async throws {
        let (channel, socket) = await makeChannel()
        async let result = channel.call("session.list")
        try await waitUntil { socket.sent.count == 1 }
        let id = try #require(socket.sent[0]["id"]?.intValue)
        socket.deliver(#"{"jsonrpc":"2.0","id":\#(id),"error":{"code":4001,"message":"invalid_params"}}"#)

        do {
            _ = try await result
            Issue.record("Expected an error")
        } catch {
            #expect(error as? GatewayError == .rpc(code: 4001, message: "invalid_params"))
        }
    }

    @Test func eventsAreStreamed() async throws {
        let (channel, socket) = await makeChannel()
        socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"message.delta","session_id":"s1","seq":7,"payload":{"text":"Hi"}}}"#
        )
        var iterator = channel.events.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event == GatewayEvent(type: "message.delta", sessionID: "s1", seq: 7, payload: ["text": "Hi"]))
    }

    @Test func closedSocketFailsPendingCalls() async throws {
        let (channel, socket) = await makeChannel()
        async let result = channel.call("profiles.list")
        try await waitUntil { socket.sent.count == 1 }
        socket.close()
        do {
            _ = try await result
            Issue.record("Expected an error")
        } catch {
            #expect(error as? GatewayError == .disconnected)
        }
        await #expect(throws: GatewayError.disconnected) { try await channel.call("profiles.list") }
    }

    @Test func silentSocketIsClosedAfterTheLimit() async throws {
        let socket = FakeSocket()
        // The limit is many heartbeats long, so a slow machine still pings before it gives up.
        let channel = JSONRPCChannel(
            socket: socket, heartbeatInterval: .milliseconds(20), silenceLimit: .milliseconds(300))
        await channel.start()
        try await waitUntil { socket.sent.contains { $0["method"] == "gateway.ping" } }
        // Nothing answers, so the channel closes the socket once the silence limit passes.
        try await waitUntil { socket.isClosed }
        await #expect(throws: GatewayError.timedOut) { try await channel.call("profiles.list") }
    }

    @Test func backoffDoublesToACap() {
        #expect(Backoff.delay(attempt: 0) == .milliseconds(300))
        #expect(Backoff.delay(attempt: 1) == .milliseconds(600))
        #expect(Backoff.delay(attempt: 5) == .milliseconds(9_600))
        #expect(Backoff.delay(attempt: 6) == .milliseconds(15_000))
        #expect(Backoff.delay(attempt: 99) == .milliseconds(15_000))
    }
}

/// Polls a main-actor `condition` until it holds, failing after a second.
@MainActor
func waitUntilOnMain(_ condition: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Condition never became true")
}

/// Polls `condition` until it holds, failing after a second.
func waitUntil(_ condition: @escaping @Sendable () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Condition never became true")
}
