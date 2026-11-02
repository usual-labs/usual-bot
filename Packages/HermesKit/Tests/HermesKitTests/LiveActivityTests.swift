import Foundation
import Testing

@testable import HermesKit

@Suite("Live activity")
struct LiveActivityTests {
    private func event(_ type: String, _ payload: JSONValue = [:]) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "s", seq: nil, payload: payload)
    }

    private func running() -> ThreadState {
        var state = ThreadState()
        state.sendLocally("go")
        return state
    }

    private func todos(_ rows: [(String, String)], revision: Int) -> JSONValue {
        let list: [JSONValue] = rows.enumerated().map { index, row in
            ["id": .string("t\(index)"), "content": .string(row.0), "status": .string(row.1)]
        }
        return ["todos": .array(list), "revision": .number(Double(revision))]
    }

    @Test func compressionShowsUntilHermesSaysItIsDone() {
        var state = running()
        state.apply(event("status.update", ["kind": "compressing", "text": "🗜 compressing 40 messages"]))
        #expect(state.live.status == "Compressing the conversation…")
        // The spinner's frames keep arriving meanwhile, and mustn't end the phase.
        state.apply(event("thinking.delta", ["text": "(◕‿◕) pondering"]))
        #expect(state.live.status == "Compressing the conversation…")
        state.apply(event("status.update", ["kind": "ready", "text": "ready"]))
        #expect(state.live.status == nil)
    }

    @Test func providerWaitsShowAndSpinnerFramesDoNot() {
        var state = running()
        state.apply(event("thinking.delta", ["text": "(◕‿◕) contemplating"]))
        #expect(state.live.status == nil)
        state.apply(event("thinking.delta", ["text": "⏳ Still waiting on the provider (30s)"]))
        #expect(state.live.status == "Still waiting on the provider (30s)")
        state.apply(event("message.delta", ["text": "Hi"]))
        #expect(state.live.status == nil)
    }

    @Test func reasoningShowsItsLatestLineUntilTheReplyStarts() {
        var state = running()
        state.apply(event("reasoning.delta", ["text": "First I look at the tests.\nThen "]))
        state.apply(event("reasoning.delta", ["text": "the logs."]))
        #expect(state.live.thought == "Then the logs.")
        state.apply(event("tool.start", ["tool_id": "1", "name": "read_file"]))
        #expect(state.live.thought == nil)
    }

    @Test func toolProgressSaysHowFarAStepHasGotAndEndsWithIt() throws {
        var state = running()
        state.apply(event("tool.start", ["tool_id": "1", "name": "terminal"]))
        state.apply(event("tool.progress", ["tool_id": "1", "percent": 42]))
        #expect(step(in: state)?.progress == "42%")
        state.apply(event("tool.progress", ["tool_id": "1", "percent": 50, "message": "Step 5 of 10"]))
        #expect(step(in: state)?.progress == "Step 5 of 10")
        state.apply(event("tool.complete", ["tool_id": "1"]))
        #expect(step(in: state)?.progress == nil)
    }

    private func step(in state: ThreadState) -> ToolStep? {
        guard case .activity(let steps) = state.items.last?.content else { return nil }
        return steps.last
    }

    @Test func aTodoListFollowsTheNewestSnapshot() {
        var state = running()
        state.apply(event("todo.updated", todos([("Read", "completed"), ("Write", "in_progress")], revision: 2)))
        #expect(state.live.todos.map(\.text) == ["Read", "Write"])
        #expect(state.live.todos.map(\.status) == [.done, .active])
        // Snapshots can overtake each other; an older one mustn't undo a newer one.
        state.apply(event("todo.updated", todos([("Read", "in_progress")], revision: 1)))
        #expect(state.live.todos.count == 2)
        state.apply(event("todo.updated", todos([], revision: 3)))
        #expect(state.live.todos.isEmpty)
    }

    @Test func aRunningChatRestoresItsTodoListAndAFinishedOneDoesNot() {
        let snapshot = todos([("Read", "in_progress")], revision: 4)
        let open = ThreadState(history: [], running: true, todoState: snapshot)
        #expect(open.live.todos.count == 1)
        let finished = ThreadState(history: [], running: false, todoState: snapshot)
        #expect(finished.live.todos.isEmpty)
    }

    @Test func helpersAreFollowedByIDAndTheirOutcomeKept() {
        var state = running()
        state.apply(event("subagent.start", ["subagent_id": "a", "goal": "Read the logs"]))
        state.apply(event("subagent.start", ["subagent_id": "b", "goal": "Check the tests"]))
        state.apply(
            event(
                "subagent.tool",
                ["subagent_id": "a", "goal": "Read the logs", "tool_name": "read_file", "tool_preview": "app.log"]))
        state.apply(event("subagent.complete", ["subagent_id": "a", "status": "completed"]))
        state.apply(event("subagent.complete", ["subagent_id": "b", "status": "timeout"]))
        #expect(state.live.helpers.map(\.goal) == ["Read the logs", "Check the tests"])
        #expect(state.live.helpers.map(\.status) == [.done, .failed])
    }

    @Test func aHelperWithNoIDIsTrackedByItsPlaceInTheBatch() {
        var state = running()
        state.apply(event("subagent.start", ["task_index": 0, "goal": "One"]))
        state.apply(event("subagent.tool", ["task_index": 0, "goal": "One", "tool_name": "terminal"]))
        state.apply(event("subagent.start", ["task_index": 1, "goal": "Two"]))
        #expect(state.live.helpers.map(\.goal) == ["One", "Two"])
        #expect(state.live.helpers.first?.tool == "terminal")
    }

    @Test func aFinishedTurnClearsWhatItWasDoing() {
        var state = running()
        state.apply(event("status.update", ["kind": "compacting"]))
        state.apply(event("todo.updated", todos([("Read", "pending")], revision: 1)))
        state.apply(event("subagent.start", ["subagent_id": "a", "goal": "Read"]))
        state.apply(event("subagent.complete", ["subagent_id": "a", "status": "completed"]))
        state.apply(event("message.complete", ["text": "Done", "status": "complete"]))
        #expect(state.live.status == nil)
        #expect(state.live.todos.isEmpty)
        #expect(state.live.helpers.isEmpty)
        // A list from before this turn can't come back late.
        state.sendLocally("again")
        state.apply(event("todo.updated", todos([("Old", "pending")], revision: 0)))
        #expect(state.live.todos.isEmpty)
    }

    @Test func aHelperInTheBackgroundOutlastsItsTurnAndLeavesWhenItFinishes() {
        var state = running()
        state.apply(event("subagent.spawn_requested", ["subagent_id": "a", "goal": "Read"]))
        state.apply(event("subagent.start", ["subagent_id": "a", "goal": "Read"]))
        state.apply(event("subagent.start", ["subagent_id": "b", "goal": "Write"]))
        state.apply(event("subagent.complete", ["subagent_id": "b", "status": "completed"]))
        state.apply(event("message.complete", ["text": "Started it", "status": "complete"]))
        #expect(state.live.helpers.map(\.id) == ["a"])
        state.apply(event("subagent.tool", ["subagent_id": "a", "goal": "Read", "tool_name": "read_file"]))
        #expect(state.live.helpers.first?.tool == "read_file")
        state.apply(event("subagent.complete", ["subagent_id": "a", "status": "completed"]))
        #expect(state.live.helpers.isEmpty)
    }

    @Test func aStoppedTurnTakesItsHelpersWithIt() {
        var state = running()
        state.apply(event("subagent.start", ["subagent_id": "a", "goal": "Read"]))
        state.apply(event("message.complete", ["status": "interrupted"]))
        #expect(state.live.helpers.isEmpty)
    }

    @Test func theLatestLineOfTheReplyIsNotShownAsAThought() {
        // Hermes sends a reply with no reasoning through here too.
        var state = running()
        state.apply(event("reasoning.available", ["text": "finished"]))
        #expect(state.live.thought == nil)
    }

    @Test func aTodoSnapshotWithNoTurnRunningIsIgnored() {
        var state = ThreadState()
        state.apply(event("todo.updated", todos([("Read", "pending")], revision: 1)))
        #expect(state.live.todos.isEmpty)
    }

    @Test func aModelFallbackIsNoted() {
        var state = running()
        state.apply(event("status.update", ["kind": "status", "text": "Switched to fallback model gpt-5"]))
        #expect(state.items.last?.content == .notice("Switched to fallback model gpt-5"))
    }

    @Test func aKeyedNotificationReplacesItselfAndClearsAway() {
        var state = running()
        state.apply(event("notification.show", ["text": "Still starting", "key": "slow"]))
        let count = state.items.count
        state.apply(event("notification.show", ["text": "Almost there", "key": "slow"]))
        #expect(state.items.count == count)
        #expect(state.items.last?.content == .notice("Almost there"))
        state.apply(event("notification.clear", ["key": "slow"]))
        #expect(state.items.count == count - 1)
    }

    @Test func aNotificationDoesNotBreakAReplyInTwo() {
        var state = running()
        state.apply(event("message.delta", ["text": "Hello "]))
        state.apply(event("notification.show", ["text": "Heads up"]))
        state.apply(event("message.delta", ["text": "there"]))
        #expect(state.draft == "Hello there")
    }

    @Test func aReplyThatArrivedBeforeAClearedNoticeStillCounts() {
        var state = ThreadState()
        state.apply(event("notification.show", ["text": "Starting", "key": "slow"]))
        state.sendLocally("go")
        state.apply(event("notification.clear", ["key": "slow"]))
        state.apply(event("message.delta", ["text": "Hi"]))
        state.apply(event("message.interim", ["already_streamed": true]))
        state.apply(event("message.complete", ["text": "Hi", "status": "complete"]))
        #expect(state.items.filter { $0.content == .assistant("Hi") }.count == 1)
    }

    @Test func noneOfItIsCachedAndOldCachesStillLoad() throws {
        var state = running()
        state.apply(event("todo.updated", todos([("Read", "pending")], revision: 1)))
        state.apply(event("notification.show", ["text": "Note", "key": "k"]))
        let data = try JSONEncoder().encode(state)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("todos"))
        #expect(!text.contains("keyedNotices"))
        let restored = try JSONDecoder().decode(ThreadState.self, from: data)
        #expect(restored.items == state.items)
        #expect(restored.live.todos.isEmpty)
        let old = #"{"items":[],"draft":"","isRunning":false,"nextID":0,"turnStart":0}"#
        #expect(throws: Never.self) { try JSONDecoder().decode(ThreadState.self, from: Data(old.utf8)) }
    }
}
