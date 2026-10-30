import Foundation
import Testing

@testable import HermesKit

@MainActor
struct SideQuestionTests {
    private func openThread(running: Bool = false) async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume",
            result: ["session_id": "live-1", "running": .bool(running), "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    private func answer(_ payload: JSONValue) -> GatewayEvent {
        GatewayEvent(type: "btw.complete", sessionID: "live-1", seq: nil, payload: payload)
    }

    @Test func btwAsksOnTheSideEvenWhileTheAgentWorks() async throws {
        let (thread, gateway) = try await openThread(running: true)
        thread.send("/btw which file are you editing?")
        let params = try await gateway.answer(1, method: "prompt.btw", result: ["task_id": "btw_a1b2c3"])
        #expect(params == ["session_id": "live-1", "text": "which file are you editing?"])
        try await waitUntilOnMain { thread.sideQuestions.first?.id == "btw_a1b2c3" }
        #expect(thread.sideQuestions.first?.answer == .waiting)
        // Nothing joins the transcript, and the turn isn't steered.
        #expect(thread.state.items.isEmpty)

        thread.apply(
            answer(["task_id": "btw_a1b2c3", "question": "which file are you editing?", "text": "src/app.ts"]))
        #expect(thread.sideQuestions.first?.answer == .answered("src/app.ts"))
        #expect(thread.state.items.isEmpty)
        thread.dismiss(thread.sideQuestions[0])
        #expect(thread.sideQuestions.isEmpty)
    }

    @Test func anAnswerBeforeItsTaskIDStillLands() async throws {
        let (thread, gateway) = try await openThread()
        thread.askOnTheSide("why?")
        try await waitUntilOnMain { gateway.socket.sent.count > 1 }
        thread.apply(answer(["task_id": "btw_x", "question": "why?", "text": "Because."]))
        #expect(thread.sideQuestions.map(\.answer) == [.answered("Because.")])
        _ = try await gateway.answer(1, method: "prompt.btw", result: ["task_id": "btw_x"])
        // sleep-ok: nothing should change, so there is no event to wait for
        try await Task.sleep(for: .milliseconds(20))
        #expect(thread.sideQuestions.map(\.id) == ["btw_x"])
    }

    @Test func failuresSayWhy() async throws {
        let (thread, gateway) = try await openThread()
        thread.askOnTheSide("one")
        _ = try await gateway.answer(1, method: "prompt.btw", error: (4012, "text required"))
        try await waitUntilOnMain { thread.sideQuestions.first?.answer == .failed("text required") }

        thread.apply(answer(["task_id": "btw_y", "question": "two", "text": "error: model unavailable"]))
        #expect(
            thread.sideQuestions.last
                == SideQuestion(id: "btw_y", question: "two", answer: .failed("model unavailable")))
    }

    @Test func onlyBtwWithWordsIsASideQuestion() {
        #expect(ChatThread.sideQuestion(in: "/btw  how long left? ") == "how long left?")
        #expect(ChatThread.sideQuestion(in: "/BTW x") == "x")
        #expect(ChatThread.sideQuestion(in: "/btw") == nil)
        #expect(ChatThread.sideQuestion(in: "/btwx hi") == nil)
        #expect(ChatThread.sideQuestion(in: "btw hi") == nil)
    }
}
