import Foundation
import Testing

@testable import HermesKit

@MainActor
struct EditTests {
    private let history: JSONValue = .array([
        ["role": "user", "text": "First", "row_id": 1], ["role": "assistant", "text": "One", "row_id": 2],
        ["role": "user", "text": "Second", "row_id": 3], ["role": "assistant", "text": "Two", "row_id": 4],
    ])

    private func openThread() async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": history])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    private func event(_ type: String, _ payload: JSONValue = [:]) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "live-1", seq: nil, payload: payload)
    }

    private let storedTurn: [JSONValue] = [
        ["role": "user", "text": "From the Mac", "row_id": 5], ["role": "assistant", "text": "Reply", "row_id": 6],
    ]

    private func history(with turn: [JSONValue]) -> JSONValue {
        guard case .array(let rows) = history else { return [:] }
        return ["messages": .array(rows + turn)]
    }

    /// The gateway tells other devices a turn began, but not what was asked.
    @Test func aMessageFromAnotherDeviceAppearsWhereItsTurnBegan() async throws {
        let (thread, gateway) = try await openThread()
        let loadBefore = thread.transcriptLoad
        thread.apply(event("message.start"))
        thread.apply(event("tool.start", ["tool_id": "t1", "name": "web_search"]))
        thread.apply(event("message.delta", ["text": "Reply"]))
        thread.apply(event("message.complete", ["status": "complete"]))
        let params = try await gateway.answer(1, method: "session.history", result: history(with: storedTurn))
        #expect(params == ["session_id": "live-1"])
        try await waitUntilOnMain { thread.state.items.count == 7 }
        #expect(thread.state.items[4].content == .user("From the Mac"))
        #expect(thread.state.items[4].rowID == 5)
        if case .activity = thread.state.items[5].content {} else { Issue.record("The steps should follow it") }
        #expect(thread.state.items[6].content == .assistant("Reply"))
        // Reloading would pull you away from what you're reading.
        #expect(thread.transcriptLoad == loadBefore)
    }

    @Test func yourOwnTurnIsntReadBack() async throws {
        let (thread, gateway) = try await openThread()
        thread.send("Third")
        _ = try await gateway.answer(1, method: "prompt.submit", result: [:])
        thread.apply(event("message.start"))
        thread.apply(event("message.complete", ["status": "complete", "text": "Three"]))
        thread.send("Fourth")
        _ = try await gateway.answer(2, method: "prompt.submit", result: [:])
    }

    @Test func aMessageSentDuringTheReadBackStays() async throws {
        let (thread, gateway) = try await openThread()
        thread.apply(event("message.start"))
        thread.apply(event("message.complete", ["status": "complete", "text": "Reply"]))
        thread.send("Next")
        let stored = storedTurn + [["role": "user", "text": "Next"]]
        _ = try await gateway.answer(1, method: "session.history", result: history(with: stored))
        _ = try await gateway.answer(2, method: "prompt.submit", result: [:])
        try await waitUntilOnMain { thread.state.items.count == 7 }
        #expect(thread.state.items[4].content == .user("From the Mac"))
        #expect(thread.state.items.last?.content == .user("Next"))
    }

    @Test func aFailedTurnKeepsItsError() async throws {
        let (thread, gateway) = try await openThread()
        thread.apply(event("message.start"))
        thread.apply(event("message.complete", ["status": "error", "text": "It broke"]))
        thread.send("Next")
        _ = try await gateway.answer(1, method: "prompt.submit", result: [:])
        #expect(thread.state.items.contains { $0.content == .notice("It broke") })
    }

    @Test func undoTakesBackTheLastExchangeAndReloads() async throws {
        let (thread, gateway) = try await openThread()
        #expect(thread.lastSent?.content == .user("Second"))
        let loadBefore = thread.transcriptLoad
        async let undone = thread.undo()
        let params = try await gateway.answer(1, method: "session.undo", result: ["removed": 2])
        #expect(params == ["session_id": "live-1"])
        _ = try await gateway.answer(
            2, method: "session.history",
            result: ["messages": .array([["role": "user", "text": "First"], ["role": "assistant", "text": "One"]])])
        #expect(await undone)
        #expect(thread.state.items.map(\.content) == [.user("First"), .assistant("One")])
        #expect(thread.transcriptLoad == loadBefore + 1)
    }

    @Test func undoFallsBackToTheLocalCopy() async throws {
        let (thread, gateway) = try await openThread()
        async let undone = thread.undo()
        _ = try await gateway.answer(1, method: "session.undo", result: ["removed": 2])
        _ = try await gateway.answer(2, method: "session.history", error: (5000, "busy"))
        #expect(await undone)
        #expect(thread.state.items.map(\.content) == [.user("First"), .assistant("One")])
    }

    @Test func refusedUndoSaysWhyAndKeepsTheMessages() async throws {
        let (thread, gateway) = try await openThread()
        async let undone = thread.undo()
        _ = try await gateway.answer(1, method: "session.undo", error: (4009, "a reply is running"))
        #expect(await undone == false)
        #expect(thread.state.items.count == 5)
        #expect(thread.state.items.last?.content == .notice("Couldn't undo: a reply is running"))
    }

    @Test func editUndoesThenSendsTheNewText() async throws {
        let (thread, gateway) = try await openThread()
        async let edited: Void = thread.edit("Second, but shorter")
        _ = try await gateway.answer(1, method: "session.undo", result: ["removed": 2])
        _ = try await gateway.answer(
            2, method: "session.history",
            result: ["messages": .array([["role": "user", "text": "First"], ["role": "assistant", "text": "One"]])])
        await edited
        let submit = try await gateway.answer(3, method: "prompt.submit", result: ["status": "streaming"])
        #expect(submit["text"] == "Second, but shorter")
        #expect(thread.state.items.map(\.content) == [.user("First"), .assistant("One"), .user("Second, but shorter")])
    }

    @Test func aFailedEditGivesTheTextBack() async throws {
        let (thread, gateway) = try await openThread()
        async let edited: Void = thread.edit("Second, but shorter")
        _ = try await gateway.answer(1, method: "session.undo", error: (4009, "a reply is running"))
        await edited
        #expect(thread.prefill == "Second, but shorter")
        #expect(thread.state.items.count == 5)
    }

    @Test func editKeepsTextAndFilesButNotImages() {
        let item = TranscriptItem(
            id: 0, content: .user("See these\n\n@image:/tmp/a.png\n@file:/work/notes.md"))
        #expect(ChatThread.editableText(of: item) == "See these\n\n@file:/work/notes.md")
    }
}
