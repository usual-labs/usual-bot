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
