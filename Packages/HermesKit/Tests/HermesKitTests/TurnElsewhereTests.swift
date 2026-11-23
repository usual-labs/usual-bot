import Foundation
import Testing

@testable import HermesKit

/// A message sent from another device, which reaches this one only as its turn starting.
@MainActor
struct TurnElsewhereTests {
    private static let ready: JSONValue = [
        "jsonrpc": "2.0", "method": "event",
        "params": ["type": "gateway.ready", "payload": ["session_authority": true, "replay_epoch": "e1"]],
    ]
    private static let image = "/home/sample/.hermes/images/iban.png"

    private func open() async throws -> (ChatThread, ScriptedGateway, Task<Void, Never>) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        try gateway.socket.deliver(Self.ready)
        #expect(try await channel.waitUntilReady().dialect == .canonical)
        let thread = ChatThread(contactID: "scout", channel: { channel })
        let events = channel.events
        let routing = Task { @MainActor in for await event in events { thread.apply(event) } }
        thread.open(knownID: "local-chat", dialect: .canonical)
        _ = try await gateway.answer(
            0, method: "session.resume",
            result: [
                "session_id": "local-chat", "running": false, "pending": [],
                "display_messages": [["role": "user", "text": "Hi"], ["role": "assistant", "text": "Hello"]],
            ])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway, routing)
    }

    private func event(_ type: String, _ payload: JSONValue = [:]) -> JSONValue {
        [
            "jsonrpc": "2.0", "method": "event",
            "params": ["type": .string(type), "session_id": "local-chat", "payload": payload],
        ]
    }

    private func started(_ id: String, _ text: String) -> JSONValue {
        event(
            "session.info",
            [
                "running": true,
                "pending": [
                    [
                        "admission_id": "adm-1", "input_id": .string(id), "text": .string(text),
                        "status": "started", "controls": [],
                    ]
                ],
            ])
    }

    /// The gateway's history once the turn is stored: the turn before, then this one.
    private func history(_ prompt: String) -> JSONValue {
        [
            "messages": [
                ["role": "user", "text": "Hi", "row_id": 1], ["role": "assistant", "text": "Hello", "row_id": 2],
                ["role": "user", "text": .string(prompt), "row_id": 3],
                ["role": "assistant", "text": "Got it.", "row_id": 4],
            ]
        ]
    }

    private func userTexts(_ thread: ChatThread) -> [String] {
        thread.state.items.compactMap { if case .user(let text) = $0.content { text } else { nil } }
    }

    @Test func aMessageFromAnotherDeviceShowsAsItsTurnStarts() async throws {
        let (thread, gateway, routing) = try await open()
        defer { routing.cancel() }
        try gateway.socket.deliver(event("message.start"))
        try gateway.socket.deliver(started("phone-1", "Here's my IBAN"))
        try await waitUntilOnMain { userTexts(thread) == ["Hi", "Here's my IBAN"] }
        try gateway.socket.deliver(event("message.delta", ["text": "Got it."]))
        try gateway.socket.deliver(event("message.complete", ["text": "Got it.", "status": "complete"]))

        // Once stored, its row takes the place of the words: the image comes with it.
        let stored = "Here's my IBAN\n\n[Image attached at: \(Self.image)]\n[screenshot]"
        _ = try await gateway.answer(1, method: "session.history", result: history(stored))
        try await waitUntilOnMain { userTexts(thread) == ["Hi", stored] }
        let prompt = try #require(thread.state.items.first { $0.content == .user(stored) })
        #expect(prompt.rowID == 3)
        #expect(thread.state.items.firstIndex(of: prompt) == 2)
    }

    @Test func anImageSentWithoutWordsWaitsForItsStoredRow() async throws {
        let (thread, gateway, routing) = try await open()
        defer { routing.cancel() }
        try gateway.socket.deliver(event("message.start"))
        try gateway.socket.deliver(started("phone-1", ""))
        try gateway.socket.deliver(event("message.complete", ["text": "Got it.", "status": "complete"]))
        let stored = "What do you see in this image?\n\n[Image attached at: \(Self.image)]"
        _ = try await gateway.answer(1, method: "session.history", result: history(stored))
        try await waitUntilOnMain { userTexts(thread) == ["Hi", stored] }
    }

    @Test func aStoppedTurnStillGetsItsImage() async throws {
        let (thread, gateway, routing) = try await open()
        defer { routing.cancel() }
        try gateway.socket.deliver(event("message.start"))
        try gateway.socket.deliver(started("phone-1", "Fill in the form"))
        try await waitUntilOnMain { userTexts(thread) == ["Hi", "Fill in the form"] }
        try gateway.socket.deliver(event("message.complete", ["status": "interrupted"]))
        let stored = "Fill in the form\n\n[Image attached at: \(Self.image)]"
        _ = try await gateway.answer(1, method: "session.history", result: history(stored))
        try await waitUntilOnMain { userTexts(thread) == ["Hi", stored] }
    }

    @Test func turnsHermesStartsWaitForTheirStoredRow() async throws {
        let (thread, gateway, routing) = try await open()
        defer { routing.cancel() }
        for id in [#"["cron","agent:main","f00d"]"#, "bot:d868cd", "widget-1F2E", "phone-2"] {
            try gateway.socket.deliver(event("message.start"))
            try gateway.socket.deliver(started(id, id == "phone-2" ? "Typed" : "[Cronjob \"Brief\" output]"))
            try gateway.socket.deliver(event("message.complete", ["status": "interrupted"]))
        }
        // Only the typed one, the last, shows before its row is read.
        try await waitUntilOnMain { userTexts(thread).last == "Typed" }
        #expect(userTexts(thread) == ["Hi", "Typed"])
    }
}
