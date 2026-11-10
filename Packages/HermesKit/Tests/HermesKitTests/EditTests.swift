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
        let last = try #require(thread.lastSent)
        async let edited: Void = thread.edit(last, to: "Second, but shorter")
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
        let last = try #require(thread.lastSent)
        async let edited: Void = thread.edit(last, to: "Second, but shorter")
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

    // MARK: - Further back

    @Test func editingAnEarlierMessageCutsTheChatAtItsRow() async throws {
        let (thread, gateway) = try await openThread()
        let first = thread.state.items[0]
        #expect(thread.rewindCost(of: first) == .init(messages: 3, fromHermes: 0, steps: 0, reachesBack: true))
        #expect(thread.rewindCost(of: thread.state.items[2])?.needsConfirmation == false)
        async let edited: Void = thread.edit(first, to: "First, again")
        let submit = try await gateway.answer(1, method: "prompt.submit", result: ["status": "streaming"])
        await edited
        #expect(
            submit == [
                "session_id": "live-1", "text": "First, again", "truncate_before_row_id": 1, "confirm_truncate": true,
                "confirm_deep_truncate": true, "confirm_empty_truncate": true,
            ])
        #expect(thread.state.items.map(\.content) == [.user("First, again")])
        #expect(thread.state.isRunning)
    }

    /// Messages sent since the chat opened have no row here until the gateway's copy is read.
    @Test func aMessageSentThisSessionIsFoundInTheGatewaysCopy() async throws {
        let (thread, gateway) = try await openThread()
        thread.send("Second")
        _ = try await gateway.answer(1, method: "prompt.submit", result: [:])
        thread.apply(event("message.start"))
        thread.apply(event("message.complete", ["status": "complete", "text": "Two again"]))
        thread.send("Third")
        _ = try await gateway.answer(2, method: "prompt.submit", result: [:])
        thread.apply(event("message.start"))
        thread.apply(event("message.complete", ["status": "complete", "text": "Three"]))
        let sent = try #require(thread.state.items.first { $0.content == .user("Second") && $0.rowID == nil })
        async let edited: Void = thread.edit(sent, to: "Second, once more")
        let stored: [JSONValue] = [
            ["role": "user", "text": "Second", "row_id": 5], ["role": "assistant", "text": "Two again", "row_id": 6],
            ["role": "user", "text": "Third", "row_id": 7], ["role": "assistant", "text": "Three", "row_id": 8],
        ]
        _ = try await gateway.answer(3, method: "session.history", result: history(with: stored))
        let submit = try await gateway.answer(4, method: "prompt.submit", result: [:])
        await edited
        // The newer of the two messages that say "Second", and not the chat's first message.
        #expect(submit["truncate_before_row_id"] == 5)
        #expect(submit["confirm_empty_truncate"] == nil)
        #expect(thread.state.items.last?.content == .user("Second, once more"))
        #expect(thread.state.items.count == 5)
    }

    /// An answer to a question shows as yours here, but the gateway keeps no message for it.
    @Test func aLineOnlyThisDeviceHasIsntMatchedToAnotherMessage() {
        let items = [
            TranscriptItem(id: 0, content: .user("Yes"), rowID: 1),
            TranscriptItem(id: 1, content: .assistant("Which?")),
            TranscriptItem(id: 2, content: .user("Yes")),
        ]
        let stored = [items[0], items[1]]
        #expect(ChatThread.row(of: items[2], in: items, stored: stored) == nil)
        #expect(
            ChatThread.row(
                of: items[2], in: items, stored: stored + [TranscriptItem(id: 2, content: .user("Yes"), rowID: 9)]) == 9
        )
    }

    @Test func aRefusedEarlierEditKeepsTheChatAndTheText() async throws {
        let (thread, gateway) = try await openThread()
        async let edited: Void = thread.edit(thread.state.items[0], to: "First, again")
        _ = try await gateway.answer(
            1, method: "prompt.submit", error: (4018, "target user message is no longer in session history"))
        _ = try await gateway.answer(2, method: "session.history", result: ["messages": history])
        await edited
        #expect(thread.prefill == "First, again")
        #expect(
            thread.state.items.map(\.content) == [
                .user("First"), .assistant("One"), .user("Second"), .assistant("Two"),
                .notice("Couldn't replace your message: it's no longer in the chat on the gateway."),
            ])
        #expect(!thread.state.isRunning)
    }

    @Test func tryAgainAsksTheLastMessageAgain() async throws {
        let (thread, gateway) = try await openThread()
        #expect(thread.retryReply?.content == .assistant("Two"))
        async let retried: Void = thread.tryAgain()
        _ = try await gateway.answer(1, method: "session.undo", result: ["removed": 2])
        _ = try await gateway.answer(
            2, method: "session.history",
            result: ["messages": .array([["role": "user", "text": "First"], ["role": "assistant", "text": "One"]])])
        await retried
        let submit = try await gateway.answer(3, method: "prompt.submit", result: [:])
        #expect(submit["text"] == "Second")
        #expect(thread.state.items.map(\.content) == [.user("First"), .assistant("One"), .user("Second")])
    }

    /// A reply to something Hermes delivered answers no message of yours.
    @Test func tryAgainIsntOfferedOnAReplyToARoutine() {
        let routine = "[Cronjob \"Brief\" output — scheduled job, not the user.]\n\nHi"
        let state = ThreadState(
            history: [
                .init(role: "user", text: "Plan my week", rowId: 1),
                .init(role: "assistant", text: "Planned", rowId: 2),
                .init(role: "user", text: routine, rowId: 3, displayKind: "internal_notification"),
                .init(role: "assistant", text: "Noted", rowId: 4),
            ], running: false)
        let thread = ChatThread.sample("scout", state: state)
        #expect(thread.retryReply == nil)
        // Editing the message still can, and says the routine's result goes with it.
        #expect(
            thread.rewindCost(of: state.items[0]) == .init(messages: 3, fromHermes: 1, steps: 0, reachesBack: true))
    }

    @Test func tryAgainSaysWhyItCantSendAPictureAgain() {
        let state = ThreadState(
            history: [
                .init(role: "user", text: "See this\n\n@image:/tmp/a.png", rowId: 1),
                .init(role: "assistant", text: "Seen", rowId: 2),
            ], running: false)
        let thread = ChatThread.sample("scout", state: state)
        #expect(thread.retryReply != nil)
        #expect(thread.tryAgainUnavailable?.contains("picture") == true)
    }

    @Test func nothingChangesWhileAReplyRuns() async throws {
        let (thread, _) = try await openThread()
        #expect(thread.rewindUnavailable == nil)
        thread.apply(event("message.start"))
        #expect(thread.rewindUnavailable == "Wait for the reply to end, or stop it.")
        #expect(!thread.canRewind)
        thread.receive(ApprovalPrompt(id: "a1", sessionID: "live-1", command: "ls", description: "", choices: [.once]))
        #expect(thread.rewindUnavailable == "The reply is waiting on you. Answer it or stop it first.")
    }

    /// The steps a reply took stay done, which is worth saying before it's asked again.
    @Test func aReplyThatActedAsksFirst() async throws {
        let (thread, _) = try await openThread()
        thread.send("Third")
        thread.apply(event("message.start"))
        thread.apply(event("tool.start", ["tool_id": "t1", "name": "terminal"]))
        thread.apply(event("tool.complete", ["tool_id": "t1"]))
        thread.apply(event("message.complete", ["status": "complete", "text": "Done"]))
        let last = try #require(thread.lastSent)
        let cost = try #require(thread.rewindCost(of: last))
        #expect(cost == .init(messages: 1, fromHermes: 0, steps: 1, reachesBack: false))
        #expect(cost.needsConfirmation)
    }
}
