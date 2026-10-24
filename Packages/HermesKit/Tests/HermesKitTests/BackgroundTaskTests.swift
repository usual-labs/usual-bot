import Foundation
import Testing

@testable import HermesKit

@MainActor
struct BackgroundTaskTests {
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

    private func finished(_ payload: JSONValue) -> GatewayEvent {
        GatewayEvent(type: "background.complete", sessionID: "live-1", seq: nil, payload: payload)
    }

    @Test func bgRunsOnTheSideAndItsResultJoinsTheChat() async throws {
        let (thread, gateway) = try await openThread(running: true)
        var heard: [(String, String)] = []
        thread.backgroundTaskFinished = { heard.append(($0, $1)) }
        thread.send("/bg summarise last week's incidents")
        let params = try await gateway.answer(1, method: "prompt.background", result: ["task_id": "bg_9f8e7d"])
        #expect(params == ["session_id": "live-1", "text": "summarise last week's incidents"])
        try await waitUntilOnMain { thread.backgroundTasks.first?.id == "bg_9f8e7d" }
        #expect(thread.state.items.isEmpty)

        thread.apply(finished(["task_id": "bg_9f8e7d", "text": "Two incidents, both resolved."]))
        #expect(thread.backgroundTasks.isEmpty)
        #expect(
            thread.state.items.map(\.content) == [
                .background(task: "summarise last week's incidents", result: "Two incidents, both resolved.")
            ])
        #expect(heard.map(\.0) == ["summarise last week's incidents"])
        // The running turn goes on.
        #expect(thread.state.isRunning)
    }

    @Test func aResultBeforeItsTaskIDStillFindsItsTask() async throws {
        let (thread, gateway) = try await openThread()
        thread.runInBackground("check the backups")
        try await waitUntilOnMain { gateway.socket.sent.count > 1 }
        thread.apply(finished(["task_id": "bg_1", "text": "All good."]))
        #expect(thread.state.items.map(\.content) == [.background(task: "check the backups", result: "All good.")])
        #expect(thread.backgroundTasks.isEmpty)
    }

    @Test func failuresBecomeNotices() async throws {
        let (thread, gateway) = try await openThread()
        thread.runInBackground("one")
        _ = try await gateway.answer(1, method: "prompt.background", error: (5035, "backend is retiring"))
        try await waitUntilOnMain { !thread.state.items.isEmpty }
        #expect(thread.backgroundTasks.isEmpty)
        #expect(
            thread.state.items.last?.content
                == .notice("Couldn't start “one” in the background: backend is retiring"))

        thread.runInBackground("two")
        _ = try await gateway.answer(2, method: "prompt.background", result: ["task_id": "bg_2"])
        try await waitUntilOnMain { thread.backgroundTasks.first?.id == "bg_2" }
        thread.apply(finished(["task_id": "bg_2", "text": "error: no model"]))
        #expect(thread.state.items.last?.content == .notice("The background task “two” failed: no model"))
    }

    @Test func aResultInAnotherChatCountsAsUnread() async throws {
        let (thread, _) = try await openThread()
        thread.apply(finished(["task_id": "bg_elsewhere", "text": "Done."]))
        #expect(thread.unreadCount == 1)
        #expect(thread.state.items.map(\.content) == [.background(task: "A background task", result: "Done.")])
    }

    @Test func onlyBgWithWordsIsATask() {
        #expect(ChatThread.backgroundTask(in: "/bg  tidy the repo ") == "tidy the repo")
        #expect(ChatThread.backgroundTask(in: "/background tidy") == "tidy")
        #expect(ChatThread.backgroundTask(in: "/bg") == nil)
        #expect(ChatThread.backgroundTask(in: "/bgx hi") == nil)
    }
}
