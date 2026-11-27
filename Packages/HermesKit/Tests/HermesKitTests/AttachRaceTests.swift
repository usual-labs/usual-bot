import Foundation
import Testing

@testable import HermesKit

/// A chat attaching mid-reply reads a snapshot, then the reply so far, before it knows its session.
/// A reply that ended in between left "Writing…" on screen until the chat was opened again: what a
/// notification's tap found, as the push goes out just before the turn ends.
@MainActor
struct AttachRaceTests {
    private func model(on gateway: ScriptedGateway) async throws -> AppModel {
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        gateway.socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"session_authority":true}}}"#
        )
        _ = try await channel.waitUntilReady()
        model.channel = channel
        model.link = .online(.canonical)
        var contact = Contact(id: "scout", name: "Scout", details: AgentDetails(profile: "scout"))
        contact.chatID = "local-1"
        model.contacts = [contact]
        return model
    }

    private let running: JSONValue = [
        "session_id": "local-1", "running": true, "execution_generation": 3, "revision": 5,
        "subscription_id": "sub-1", "replay_epoch": "e1", "last_sequence": 10,
        "display_messages": [["role": "user", "text": "Clean up"]],
        "pending": [["admission_id": "a1", "status": "started", "input_id": "in-1", "text": "Clean up"]],
    ]

    private func event(_ type: String, seq: Int, _ payload: JSONValue) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "local-1", seq: seq, payload: payload)
    }

    @Test func aReplyThatEndsWhileTheChatAttachesEndsOnScreen() async throws {
        let gateway = ScriptedGateway()
        let model = try await model(on: gateway)
        model.openThread(for: model.contacts[0])
        let thread = try #require(model.threads["scout"])

        _ = try await gateway.answer(0, method: "session.resume", result: running)
        try await waitUntil { gateway.socket.sent.count > 1 }
        // While the reply so far is read: one frame the snapshot has, then the rest of the turn.
        model.route(event("message.delta", seq: 10, ["text": "Done"]))
        model.route(event("message.delta", seq: 11, ["text": "."]))
        model.route(event("message.complete", seq: 12, ["status": "complete"]))
        _ = try await gateway.answer(
            1, method: "session.events.since",
            result: [
                "replay_epoch": "e1", "truncated": false,
                "events": [
                    ["type": "message.delta", "seq": 10, "admission_id": "a1", "payload": ["text": "Done"]],
                    // Read after the snapshot, so it's the live event's to show.
                    ["type": "message.delta", "seq": 11, "admission_id": "a1", "payload": ["text": "."]],
                ],
            ])
        try await waitUntilOnMain { thread.isAttached }

        #expect(!thread.state.isRunning)
        #expect(thread.state.items.last?.content == .assistant("Done."))
    }

    @Test func aReplyStillRunningKeepsWriting() async throws {
        let gateway = ScriptedGateway()
        let model = try await model(on: gateway)
        model.openThread(for: model.contacts[0])
        let thread = try #require(model.threads["scout"])

        _ = try await gateway.answer(0, method: "session.resume", result: running)
        _ = try await gateway.answer(
            1, method: "session.events.since",
            result: [
                "replay_epoch": "e1", "truncated": false,
                "events": [["type": "message.delta", "seq": 9, "admission_id": "a1", "payload": ["text": "On it"]]],
            ])
        try await waitUntilOnMain { thread.isAttached }

        #expect(thread.state.isRunning)
        #expect(thread.state.draft == "On it")
    }
}
