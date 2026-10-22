import Foundation
import Testing

@testable import HermesKit

struct ThreadStateTests {
    private func event(_ type: String, _ payload: JSONValue = [:]) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "s1", seq: nil, payload: payload)
    }

    private func contents(_ state: ThreadState) -> [TranscriptItem.Content] {
        state.items.map(\.content)
    }

    @Test func historyGroupsConsecutiveToolRows() {
        let history = [
            HistoryMessage(role: "user", text: "Ship it"),
            HistoryMessage(role: "assistant", text: "On it."),
            HistoryMessage(role: "tool", name: "read_file", context: "package.json", toolCallId: "t1"),
            HistoryMessage(role: "tool", name: "terminal", context: "npm test", toolCallId: "t2"),
            HistoryMessage(role: "assistant", text: "  "),
            HistoryMessage(role: "assistant", text: "Done."),
            HistoryMessage(role: "system", text: "model switched"),
        ]
        let state = ThreadState(history: history, running: false)

        #expect(
            contents(state) == [
                .user("Ship it"), .assistant("On it."),
                .activity([
                    ToolStep(id: "t1", name: "read_file", context: "package.json", state: .done),
                    ToolStep(id: "t2", name: "terminal", context: "npm test", state: .done),
                ]),
                .assistant("Done."),
            ])
        #expect(!state.isRunning)
    }

    @Test func streamedReplyBecomesOneMessage() {
        var state = ThreadState()
        state.sendLocally("Hi")
        #expect(state.isRunning)
        state.apply(event("message.start"))
        state.apply(event("message.delta", ["text": "Hel"]))
        state.apply(event("message.delta", ["text": "lo!"]))
        #expect(state.draft == "Hello!")
        state.apply(event("message.complete", ["text": "Hello!", "status": "complete"]))

        #expect(contents(state) == [.user("Hi"), .assistant("Hello!")])
        #expect(state.draft.isEmpty)
        #expect(!state.isRunning)
    }

    @Test func toolCallsSplitTheReplyAroundOneActivityLine() {
        var state = ThreadState()
        state.apply(event("message.start"))
        state.apply(event("message.delta", ["text": "On it."]))
        state.apply(event("tool.start", ["tool_id": "t1", "name": "read_file", "context": "a.swift"]))
        #expect(state.draft.isEmpty)
        state.apply(event("tool.complete", ["tool_id": "t1", "name": "read_file", "duration_s": 1.5]))
        state.apply(event("tool.start", ["tool_id": "t2", "name": "terminal", "context": "swift test"]))
        state.apply(
            event("tool.complete", ["tool_id": "t2", "summary": "7 passed", "result": ["error": "exit 1"]]))
        state.apply(event("message.delta", ["text": "Done."]))
        state.apply(event("message.complete", ["text": "Done.", "status": "complete"]))

        #expect(
            contents(state) == [
                .assistant("On it."),
                .activity([
                    ToolStep(id: "t1", name: "read_file", context: "a.swift", duration: 1.5, state: .done),
                    ToolStep(id: "t2", name: "terminal", context: "swift test", summary: "7 passed", state: .failed),
                ]),
                .assistant("Done."),
            ])
    }

    @Test func unstreamedReplyArrivesWithCompletion() {
        var state = ThreadState()
        state.apply(event("message.start"))
        state.apply(event("message.complete", ["text": "Whole reply", "status": "complete"]))
        #expect(contents(state) == [.assistant("Whole reply")])
    }

    @Test func completionDoesNotRepeatInterimText() {
        var state = ThreadState()
        state.apply(event("message.start"))
        state.apply(event("message.delta", ["text": "Checking."]))
        state.apply(event("message.interim", ["text": "Checking.", "already_streamed": true]))
        state.apply(event("message.interim", ["text": "Not streamed note", "already_streamed": false]))
        state.apply(event("message.complete", ["text": "Not streamed note", "status": "complete"]))
        #expect(contents(state) == [.assistant("Checking."), .assistant("Not streamed note")])
    }

    @Test func stoppedTurnSaysSoAndSettlesRunningSteps() {
        var state = ThreadState()
        state.apply(event("message.start"))
        state.apply(event("tool.start", ["tool_id": "t1", "name": "terminal", "context": "sleep 60"]))
        state.apply(event("message.complete", ["text": "", "status": "interrupted"]))

        #expect(
            contents(state) == [
                .activity([ToolStep(id: "t1", name: "terminal", context: "sleep 60", state: .failed)]),
                .notice("Stopped"),
            ])
        #expect(!state.isRunning)
    }

    @Test func failedTurnShowsTheErrorAsANotice() {
        var state = ThreadState()
        state.apply(event("message.start"))
        state.apply(event("message.delta", ["text": "partial tex"]))
        state.apply(event("message.complete", ["text": "Error: provider timed out", "status": "error"]))
        #expect(contents(state) == [.notice("Error: provider timed out")])
    }

    @Test func otherSessionsEventsAndUnknownTypesAreHarmless() {
        var state = ThreadState()
        state.apply(event("status.update", ["kind": "goal", "text": "x"]))
        state.apply(event("tool.complete", ["tool_id": "missing"]))
        state.apply(event("error", ["message": "compression failed"]))
        #expect(contents(state) == [.notice("compression failed")])
    }
}
