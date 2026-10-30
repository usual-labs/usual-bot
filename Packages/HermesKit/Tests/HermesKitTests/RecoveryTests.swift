import Foundation
import Testing

@testable import HermesKit

@MainActor
struct RecoveryTests {
    private func open(_ thread: ChatThread, _ gateway: ScriptedGateway, at index: Int, session: String) async throws {
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            index, method: "session.resume",
            result: ["session_id": .string(session), "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }
    }

    private func makeThread() async -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "ops", channel: { channel })
        thread.replayEpoch = "epoch-1"
        return (thread, gateway)
    }

    @Test func aShortDropIsReplayed() async throws {
        let (thread, gateway) = await makeThread()
        try await open(thread, gateway, at: 0, session: "live-1")
        thread.apply(GatewayEvent(type: "message.complete", sessionID: "live-1", seq: 41, payload: ["text": ""]))
        thread.askOnTheSide("how long left?")
        _ = try await gateway.answer(1, method: "prompt.btw", result: ["task_id": "btw_1"])
        try await waitUntilOnMain { thread.sideQuestions.first?.id == "btw_1" }

        thread.detach()
        try await open(thread, gateway, at: 2, session: "live-1")
        let params = try await gateway.answer(
            3, method: "session.events.since",
            result: [
                "epoch": "epoch-1", "truncated": false,
                "events": [
                    ["type": "message.delta", "session_id": "live-1", "seq": 42, "payload": ["text": "x"]],
                    [
                        "type": "btw.complete", "session_id": "live-1", "seq": 43,
                        "payload": ["task_id": "btw_1", "question": "how long left?", "text": "About ten minutes."],
                    ],
                ],
            ])
        #expect(params == ["session_id": "live-1", "last_seen": 41])
        try await waitUntilOnMain { thread.sideQuestions.first?.answer == .answered("About ten minutes.") }
    }

    @Test func aQuestionAskedDuringRecoveryIsNotLost() async throws {
        let (thread, gateway) = await makeThread()
        try await open(thread, gateway, at: 0, session: "live-1")
        thread.apply(GatewayEvent(type: "message.complete", sessionID: "live-1", seq: 41, payload: ["text": ""]))

        thread.detach()
        try await open(thread, gateway, at: 1, session: "live-1")
        thread.askOnTheSide("why?")
        // The gateway can't replay, but the question went to the session the chat is on now.
        _ = try await gateway.answer(2, method: "session.events.since", result: ["truncated": true])
        _ = try await gateway.answer(3, method: "prompt.btw", result: ["task_id": "btw_2"])
        try await waitUntilOnMain { thread.sideQuestions.first?.id == "btw_2" }
        #expect(thread.sideQuestions.first?.answer == .waiting)
    }

    @Test func aNewSessionLosesSideAnswersButFindsBackgroundResults() async throws {
        let (thread, gateway) = await makeThread()
        var asked: [String] = []
        thread.storedAnswer = { id in
            asked.append(id)
            return "All three backups are fine."
        }
        try await open(thread, gateway, at: 0, session: "live-1")
        thread.askOnTheSide("why?")
        _ = try await gateway.answer(1, method: "prompt.btw", result: ["task_id": "btw_9"])
        thread.runInBackground("check the backups")
        _ = try await gateway.answer(2, method: "prompt.background", result: ["task_id": "bg_7"])
        try await waitUntilOnMain { thread.backgroundTasks.first?.id == "bg_7" }

        // The gateway tore the chat down while the app was away; it attaches to a new session.
        thread.detach()
        try await open(thread, gateway, at: 3, session: "live-2")
        try await waitUntilOnMain { thread.backgroundTasks.isEmpty }
        #expect(asked == ["bg_7"])
        #expect(
            thread.sideQuestions.first?.answer
                == .failed("The answer was lost while Usual Bot was offline. Ask again."))
        #expect(
            thread.state.items.map(\.content) == [
                .background(task: "check the backups", result: "All three backups are fine.")
            ])

        // The live event arriving late doesn't add it twice.
        thread.apply(
            GatewayEvent(
                type: "background.complete", sessionID: "live-2", seq: nil,
                payload: ["task_id": "bg_7", "text": "All three backups are fine."]))
        #expect(thread.state.items.count == 1)
    }

    @Test func backgroundResultsSurviveReloadsInTimeOrder() {
        let kept = [
            BackgroundResult(
                taskID: "bg_1", task: "costs", result: "Down 4%.", date: Date(timeIntervalSince1970: 150))
        ]
        let state = ThreadState(
            history: [
                HistoryMessage(role: "user", text: "Hi", timestamp: 100),
                HistoryMessage(role: "assistant", text: "Hello", timestamp: 120),
                HistoryMessage(role: "user", text: "Later", timestamp: 200),
            ], running: false, kept: kept)
        #expect(
            state.items.map(\.content) == [
                .user("Hi"), .assistant("Hello"), .background(task: "costs", result: "Down 4%."), .user("Later"),
            ])
    }

    @Test func sideWorkIsCachedBetweenLaunches() throws {
        let cached = CachedThread(
            state: ThreadState(), lastViewed: nil, unreadCount: 0,
            sideQuestions: [SideQuestion(id: "btw_1", question: "q", answer: .answered("a"))],
            backgroundTasks: [BackgroundTask(id: "bg_1", task: "t")],
            backgroundResults: [BackgroundResult(taskID: "bg_0", task: "t0", result: "r0", date: .distantPast)])
        let decoded = try JSONDecoder().decode(CachedThread.self, from: JSONEncoder().encode(cached))
        #expect(decoded == cached)
        let thread = ChatThread(contactID: "ops", cached: decoded, channel: { nil })
        #expect(thread.sideQuestions.count == 1)
        #expect(thread.backgroundTasks.map(\.id) == ["bg_1"])
        // A cache from before these existed still loads.
        let old = try JSONDecoder().decode(
            CachedThread.self,
            from: Data(
                #"{"state":{"items":[],"draft":"","isRunning":false,"nextID":0,"turnStart":0},"unreadCount":0}"#.utf8))
        #expect(old.sideQuestions == nil)
    }
}
