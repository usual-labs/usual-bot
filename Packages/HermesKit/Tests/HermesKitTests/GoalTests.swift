import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// A goal's state, its place in the chat and its actions. The recorded case plays traffic from a
/// throwaway Hermes 0.23.1 gateway (`Fixtures/README.md`); the rest script the gateway's answers.
@MainActor
struct GoalTests {
    private static let ready: JSONValue = [
        "jsonrpc": "2.0", "method": "event",
        "params": ["type": "gateway.ready", "payload": ["session_authority": true, "replay_epoch": "e1"]],
    ]
    private static let goalCommand = SlashCommand(name: "/goal", description: "", kind: .command)

    private func goal(
        _ status: String = "active", used: Int = 1, reason: String? = nil, check: String? = nil,
        subgoals: [JSONValue] = []
    ) -> JSONValue {
        var fields: [String: JSONValue] = [
            "title": "Write the weekly report", "status": .string(status), "turns_used": .number(Double(used)),
            "max_turns": 20, "subgoals": .array(subgoals), "gates": [],
        ]
        fields["paused_reason"] = reason.map(JSONValue.string)
        fields["last_reason"] = check.map(JSONValue.string)
        return ["goal": .object(fields), "loop": .null, "heartbeat": .null, "revision": "r"]
    }

    /// A chat open on the gateway's own listener, with its events routed to it as `AppModel` does.
    private func open(resume: JSONValue, control: JSONValue? = nil, cached: CachedThread? = nil) async throws
        -> (ChatThread, ScriptedGateway, Task<Void, Never>)
    {
        let gateway = ScriptedGateway()
        gateway.socket.goalControl.withLock { $0 = control }
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        try gateway.socket.deliver(Self.ready)
        #expect(try await channel.waitUntilReady().dialect == .canonical)
        let thread = ChatThread(contactID: "scout", cached: cached, channel: { channel })
        thread.commands = [Self.goalCommand]
        let events = channel.events
        let routing = Task { @MainActor in for await event in events { thread.apply(event) } }
        thread.open(knownID: "local-chat", dialect: .canonical)
        _ = try await gateway.answer(0, method: "session.resume", result: resume)
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway, routing)
    }

    private let idle: JSONValue = ["session_id": "local-chat", "running": false, "display_messages": [], "pending": []]

    private func continuation(_ status: String, id: String = "adm-next") -> JSONValue {
        [
            "admission_id": .string(id), "input_id": "[\"goal-continuation\",\"agent:main:local\",\"1f\"]",
            "text": "[Continuing toward your standing goal]\nGoal: Write the weekly report\n\nContinue working.",
            "status": .string(status), "controls": [], "steering": false,
        ]
    }

    private func running(_ rows: [JSONValue]) -> JSONValue {
        [
            // No `replay_epoch`, so attaching doesn't read the reply so far.
            "session_id": "local-chat", "running": true, "execution_generation": 4,
            "display_messages": [["role": "user", "text": "Write the weekly report"]],
            "pending": .array(rows),
        ]
    }

    private func event(_ type: String, _ payload: JSONValue, seq: Int) -> JSONValue {
        [
            "jsonrpc": "2.0", "method": "event",
            "params": [
                "type": .string(type), "session_id": "local-chat", "replay_epoch": "s1", "seq": .number(Double(seq)),
                "payload": payload,
            ],
        ]
    }

    // MARK: - Recorded

    /// The whole of a goal as the gateway ran it: set with `/goal`, carried on by Hermes, stopped
    /// mid-reply, continued, judged done and cleared. Each recorded request is one the app makes
    /// here, by itself or when the test acts, and is answered as the gateway answered it.
    @Test func aGoalIsSetCarriedOnStoppedContinuedAndFinished() async throws {
        let recording = try RecordedGatewayTests.Recording("canonical-goal")
        let read = try #require(recording.entries.first { $0.frame["result"]?["control"] != nil })
        let resume = try #require(recording.entries.first { $0.frame["result"]?["display_messages"] != nil })
        let (thread, gateway, routing) = try await open(
            resume: try #require(resume.frame["result"]), control: read.frame["result"]?["control"])
        defer { routing.cancel() }
        var seenWorkingBetweenReplies = false
        var starts = 0
        var delivered = 0
        // `session.resume` was the first.
        var answered = 1
        let acts: [(method: String, ready: @MainActor () -> Bool, act: @MainActor () -> Void)] = [
            ("command.dispatch", { thread.goal == nil }, { thread.send("/goal Write the weekly report") }),
            ("prompt.submit", { true }, {}),
            (
                "session.control",
                // Into its second reply, the one Hermes started.
                { thread.goal?.turnsUsed == 1 && thread.state.isRunning && thread.state.draft.hasPrefix("Step") },
                {
                    #expect(thread.goalPhase == .working)
                    #expect(thread.goal?.lastCheck == "The summary section is still missing.")
                    thread.stopGoal()
                }
            ),
            ("session.interrupt", { true }, {}),
            (
                "session.control", { thread.goalPhase == .stopped && !thread.state.isRunning },
                {
                    #expect(thread.goal?.stopReason == .byYou)
                    thread.continueGoal()
                }
            ),
            ("prompt.submit", { true }, {}),
            (
                "session.control", { thread.goalPhase == .done && !thread.state.isRunning },
                {
                    #expect(thread.goal?.lastCheck == "The report has every section.")
                    thread.clearGoal()
                }
            ),
        ]
        var steps = acts[...]
        var swaps: [String: String] = [:]
        var requestIDs: [JSONValue: JSONValue] = [:]
        let start = try #require(recording.entries.firstIndex { $0.frame["result"]?["control"] != nil })
        for entry in recording.entries[(start + 1)...] {
            if entry.direction == "out" {
                let next = steps.popFirst()
                let step = try #require(next, "The recording has a request the test doesn't make")
                // The gateway sent these before it got the request, so the app has seen them by then.
                let seen = delivered
                try await waitUntilOnMain { thread.lastSeq >= seen }
                try await waitUntilOnMain(step.ready)
                // Counted in order: one the app sends by itself may already be out.
                let sent = answered
                answered += 1
                step.act()
                try await waitUntil { gateway.socket.sent.count > sent }
                let request = gateway.socket.sent[sent]
                #expect(request["method"]?.stringValue == step.method)
                #expect(entry.frame["method"]?.stringValue == step.method)
                #expect(request["params"]?["profile"] == "scout")
                for key in ["action", "name", "arg", "text", "execution_generation"] {
                    #expect(request["params"]?[key] == entry.frame["params"]?[key], "\(step.method) \(key)")
                }
                requestIDs[entry.frame["id"] ?? .null] = request["id"]
                if let recorded = entry.frame["params"]?["submission_id"]?.stringValue {
                    swaps[recorded] = try #require(request["params"]?["submission_id"]?.stringValue)
                }
                continue
            }
            var frame = entry.frame
            if let id = frame["id"], case .object(var fields) = frame {
                fields["id"] = try #require(requestIDs[id])
                frame = .object(fields)
            }
            var text = String(decoding: try JSONEncoder().encode(frame), as: UTF8.self)
            for (recorded, own) in swaps { text = text.replacingOccurrences(of: recorded, with: own) }
            // Hermes queues the goal's next reply before it ends the one it judged, so the goal
            // never looks idle in between: here, just before its second reply starts.
            if frame["params"]?["type"] == "message.start" {
                starts += 1
                if starts == 2 {
                    try await waitUntilOnMain { !thread.state.isRunning && thread.goal?.turnsUsed == 1 }
                    seenWorkingBetweenReplies = thread.goalPhase == .working && thread.activity == .working
                }
            }
            // A queued message taken back ends no turn, so the chat never hears of it.
            if frame["params"]?["payload"]?["outcome"] != "cancelled" || frame["params"]?["payload"]?["status"] != nil {
                delivered = max(delivered, frame["params"]?["seq"]?.intValue ?? 0)
            }
            gateway.socket.deliver(text)
        }
        #expect(steps.isEmpty)
        #expect(seenWorkingBetweenReplies)
        try await waitUntilOnMain { thread.goal == nil }
        #expect(thread.goalPhase == nil)
        #expect(
            thread.state.items.map(\.content) == [
                .user("/goal Write the weekly report"),
                .assistant("Step done for: 'Write the weekly report'. More to do."),
                // Hermes's own turn: a line where your message would be, not its prompt.
                .notice(GatewayTurn.goalStep),
                // What it had said when it was stopped.
                .assistant("Step done "),
                .notice("You stopped the goal"),
                .notice("Stopped"),
                .notice(GatewayTurn.goalStep),
                .assistant(
                    "Step done for: '[Continuing toward your standing goal]\\nGoal: Write the weekly report\\n\\n'. More to do."
                ),
            ])
    }

    // MARK: - Reading it

    @Test func aGoalRunningElsewhereShowsWhenTheChatOpens() async throws {
        let control = goal(used: 2, check: "Two sections left.", subgoals: ["Cite sources"])
        let (thread, _, routing) = try await open(resume: running([continuation("started")]), control: control)
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goal != nil }
        #expect(
            thread.goal
                == Goal(
                    text: "Write the weekly report", turnsUsed: 2, turnsAllowed: 20, criteria: ["Cite sources"],
                    lastCheck: "Two sections left."))
        #expect(thread.goalPhase == .working)
        #expect(thread.activity == .working)
    }

    @Test func aGatewayWithoutGoalsShowsNothing() async throws {
        // Kept from the last launch; this gateway refuses the read.
        let cached = CachedThread(
            state: ThreadState(), lastViewed: nil, unreadCount: 0, goal: Goal(text: "Write the weekly report"))
        let (thread, gateway, routing) = try await open(resume: idle, cached: cached)
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goal == nil }
        #expect(thread.goalPhase == nil)
        #expect(thread.canSend)
        #expect(gateway.socket.sent.count == 1)
    }

    @Test func theGoalIsKeptForOfflineAndTheNextLaunch() throws {
        let thread = ChatThread.sample("scout", state: ThreadState())
        thread.goal = Goal(text: "Write the weekly report", status: .paused, turnsUsed: 20, turnsAllowed: 20)
        let data = try JSONEncoder().encode(thread.cacheEntry)
        let restored = ChatThread(
            contactID: "scout", cached: try JSONDecoder().decode(CachedThread.self, from: data), channel: { nil })
        #expect(restored.goal == thread.goal)
        #expect(restored.goalPhase == .stopped)
        // Offline: it shows, and nothing about it can be changed.
        #expect(!restored.canChangeGoal)
    }

    @Test func hermesSaysWhyAGoalStopped() {
        func stopped(_ reason: String?) -> Goal? { Goal(goal("paused", reason: reason)["goal"]) }
        #expect(stopped("user-paused")?.stopReason == .byYou)
        #expect(stopped(nil)?.stopReason == .byYou)
        #expect(stopped("turn budget exhausted (20/20)")?.stopReason == .outOfTurns)
        #expect(
            stopped("judged unachievable: needs the VPN password")?.stopReason == .blocked("needs the VPN password"))
        #expect(
            stopped("judge API unreachable 5 turns in a row")?.stopReason
                == .other("judge API unreachable 5 turns in a row"))
        #expect(Goal(goal("active")["goal"])?.stopReason == nil)
        // A state from a newer Hermes shows as nothing, not as something it isn't.
        #expect(Goal(goal("archived")["goal"]) == nil)
        #expect(Goal(JSONValue.null) == nil)
        let parked: JSONValue = [
            "title": "Ship it", "status": "active", "turns_used": 3, "max_turns": 20,
            "wait_barrier": ["type": "pid", "target": 4242, "reason": "the CI run"],
        ]
        #expect(Goal(parked)?.isWaiting == true)
        #expect(Goal(parked)?.waitingOn == "the CI run")
    }

    @Test func betweenRepliesAGoalIsStillWorking() async throws {
        let (thread, gateway, routing) = try await open(resume: idle, control: goal())
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goal != nil }
        // Set, and nothing running or queued: it won't go on by itself.
        #expect(thread.goalPhase == .notRunning)
        #expect(thread.activity == .idle)
        try gateway.socket.deliver(
            event("session.info", ["pending": [continuation("queued")], "running": false], seq: 1))
        try await waitUntilOnMain { thread.goalPhase == .working }
        #expect(thread.activity == .working)
        // Hermes's own turns aren't yours to edit, send now or remove.
        #expect(thread.queue.isEmpty)
        #expect(!thread.canRewind)
        try gateway.socket.deliver(event("session.info", ["pending": [], "running": false], seq: 2))
        try await waitUntilOnMain { thread.goalPhase == .notRunning }
    }

    @Test func aGoalThatEndsByItselfAlerts() async throws {
        let (thread, gateway, routing) = try await open(resume: idle, control: goal())
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goal != nil }
        let heard = Mutex<[String]>([])
        thread.goalEnded = { goal, outcome in heard.withLock { $0.append("\(goal): \(outcome)") } }
        try gateway.socket.deliver(
            event("session.control.update", ["control": goal("paused", reason: "user-paused")], seq: 1))
        try await waitUntilOnMain { thread.goalPhase == .stopped }
        try gateway.socket.deliver(event("session.control.update", ["control": goal()], seq: 2))
        try await waitUntilOnMain { thread.goalPhase == .notRunning }
        try gateway.socket.deliver(
            event(
                "session.control.update",
                ["control": goal("paused", used: 20, reason: "turn budget exhausted (20/20)")],
                seq: 3))
        try await waitUntilOnMain { thread.goalPhase == .stopped }
        try gateway.socket.deliver(event("session.control.update", ["control": goal()], seq: 4))
        try await waitUntilOnMain { thread.goalPhase == .notRunning }
        try gateway.socket.deliver(
            event("session.control.update", ["control": goal("done", check: "The report has every section.")], seq: 5))
        try await waitUntilOnMain { thread.goalPhase == .done }
        // Your own stop is no news to you.
        #expect(
            heard.withLock { $0 } == [
                "Write the weekly report: Stopped: it used all 20 of its turns.",
                "Write the weekly report: Done: The report has every section.",
            ])
    }

    // MARK: - In the chat

    @Test func theGoalsOwnTurnsReadAsALine() {
        let prompt =
            "[Continuing toward your standing goal]\nGoal: Write the weekly report\n\nContinue working toward this goal."
        #expect(
            GatewayTurn.content(text: prompt, kind: "internal_notification", title: nil)
                == .notice(GatewayTurn.goalStep))
        // Continue sends Hermes's words back as a message of this app's, with no kind.
        #expect(GatewayTurn.content(text: prompt, kind: nil, title: nil) == .notice(GatewayTurn.goalStep))
        #expect(GatewayTurn.preview(of: prompt) == GatewayTurn.goalStep)
        // So Undo goes back past them to what you last said.
        let rows: JSONValue = [
            ["role": "user", "text": "Write the weekly report", "row_id": 1],
            ["role": "assistant", "text": "Step one."],
            ["role": "user", "text": .string(prompt), "row_id": 3, "display_kind": "internal_notification"],
            ["role": "assistant", "text": "Step two."],
        ]
        #expect(CanonicalProtocol.lastSent(in: rows) == 1)
    }

    // MARK: - Your actions

    @Test func stoppingTakesBackTheTurnsHermesQueuedThenStopsTheReply() async throws {
        let mine: JSONValue = [
            "admission_id": "adm-mine", "input_id": "first", "text": "Write the weekly report", "status": "started",
            "controls": [], "steering": false,
        ]
        let (thread, gateway, routing) = try await open(
            resume: running([mine, continuation("queued")]), control: goal())
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goalPhase == .working }
        thread.stopGoal()
        #expect(!thread.canChangeGoal)
        let pause = try await gateway.answer(
            1, method: "session.control",
            result: ["control": goal("paused", reason: "user-paused"), "dispatch": ["type": "exec"]])
        #expect(pause == ["session_id": "local-chat", "action": "goal.pause", "profile": "scout"])
        // Paused first: Hermes judges an interrupted reply like any other and would carry on.
        let cancel = try await gateway.answer(
            2, method: "prompt.cancel", result: ["status": "terminal", "outcome": "cancelled"])
        #expect(cancel["admission_id"] == "adm-next")
        let interrupt = try await gateway.answer(3, method: "session.interrupt", result: [:])
        #expect(interrupt["execution_generation"] == 4)
        try await waitUntilOnMain { thread.canChangeGoal }
        #expect(thread.goalPhase == .stopped)
        #expect(thread.state.items.last?.content == .notice("You stopped the goal"))
    }

    @Test func aStopHermesRefusesLeavesTheReplyRunning() async throws {
        let (thread, gateway, routing) = try await open(resume: running([continuation("started")]), control: goal())
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goalPhase == .working }
        thread.stopGoal()
        _ = try await gateway.answer(
            1, method: "session.control", error: (4001, "session_busy"), data: ["reason": "session_busy"])
        try await waitUntilOnMain { thread.canChangeGoal }
        #expect(thread.goalPhase == .working)
        #expect(thread.state.isRunning)
        #expect(gateway.socket.sent.count == 2)
        guard case .notice(let notice) = thread.state.items.last?.content else {
            Issue.record("No notice")
            return
        }
        #expect(notice.hasPrefix("Couldn't stop the goal: "))
    }

    @Test func stoppingAReplyLeavesTheGoalAndSaysSo() async throws {
        let (thread, gateway, routing) = try await open(resume: running([continuation("started")]), control: goal())
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goalPhase == .working }
        thread.stop()
        _ = try await gateway.answer(1, method: "session.interrupt", result: [:])
        try await waitUntilOnMain {
            thread.state.items.last?.content == .notice("The goal carries on after this reply. Stop Goal ends it.")
        }
        #expect(thread.goal?.status == .active)
    }

    @Test func goalCommandsRunWhileAReplyIsUnderWay() async throws {
        let (thread, gateway, routing) = try await open(resume: running([continuation("started")]), control: goal())
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goalPhase == .working }
        // Hermes refuses a new goal mid-reply; the app says so in its own words and asks nothing.
        thread.send("/goal Something else")
        try await waitUntilOnMain { thread.state.items.last?.content == .notice(ChatThread.goalWhileReplying) }
        #expect(gateway.socket.sent.count == 1)
        // The ones that only change the goal's state go through, and the goal shows the result.
        gateway.socket.goalControl.withLock { $0 = goal("paused", reason: "user-paused") }
        thread.send("/goal pause")
        let dispatch = try await gateway.answer(
            1, method: "command.dispatch",
            result: ["type": "exec", "output": "⏸ Goal paused: Write the weekly report"])
        #expect(dispatch["arg"] == "pause")
        try await waitUntilOnMain { thread.goalPhase == .stopped }
        // Its output isn't printed: the goal above the message box says it.
        #expect(thread.state.items.last?.content == .notice(ChatThread.goalWhileReplying))
    }

    @Test func settingAGoalLeavesHermesNoticeOut() async throws {
        let (thread, gateway, routing) = try await open(resume: idle)
        defer { routing.cancel() }
        thread.send("/goal Write the weekly report")
        _ = try await gateway.answer(
            1, method: "command.dispatch",
            result: [
                "type": "send", "message": "Write the weekly report", "display": "/goal Write the weekly report",
                "notice": "⊙ Goal set (20-turn budget): Write the weekly report\nControls: /goal status · /goal pause",
            ])
        let submit = try await gateway.answer(2, method: "prompt.submit", result: ["status": "queued"])
        #expect(submit["text"] == "Write the weekly report")
        #expect(thread.state.items.map(\.content) == [.user("/goal Write the weekly report")])
    }

    @Test func whatAGoalCommandPrintsStillShowsWhenNothingChanged() async throws {
        let (thread, gateway, routing) = try await open(resume: idle, control: goal())
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goal != nil }
        thread.send("/goal status")
        _ = try await gateway.answer(
            1, method: "command.dispatch",
            result: ["type": "exec", "output": "⊙ Goal (active, 1/20 turns): Write the weekly report"])
        try await waitUntilOnMain { thread.state.items.count == 2 }
        #expect(
            thread.state.items.map(\.content) == [
                .user("/goal status"), .output("⊙ Goal (active, 1/20 turns): Write the weekly report"),
            ])
    }

    @Test func continuingSendsWhatHermesHandsBack() async throws {
        let (thread, gateway, routing) = try await open(
            resume: idle, control: goal("paused", used: 20, reason: "turn budget exhausted (20/20)"))
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goalPhase == .stopped }
        thread.continueGoal()
        let resume = try await gateway.answer(
            1, method: "session.control",
            result: [
                "control": goal(used: 0),
                "dispatch": ["type": "send", "message": "[Continuing toward your standing goal]\nGoal: Write"],
            ])
        #expect(resume["action"] == "goal.resume")
        let submit = try await gateway.answer(2, method: "prompt.submit", result: ["status": "queued"])
        #expect(submit["text"] == "[Continuing toward your standing goal]\nGoal: Write")
        try await waitUntilOnMain { thread.canChangeGoal }
        #expect(thread.goalPhase == .working)
        #expect(thread.goal?.turnsUsed == 0)
        #expect(thread.state.items.map(\.content) == [.notice(GatewayTurn.goalStep)])
    }

    @Test func aWorkingGoalIsStoppedBeforeItCanBeCleared() async throws {
        let (thread, gateway, routing) = try await open(resume: running([continuation("started")]), control: goal())
        defer { routing.cancel() }
        try await waitUntilOnMain { thread.goalPhase == .working }
        thread.clearGoal()
        thread.continueGoal()
        // sleep-ok: nothing is sent, so there's no event to wait for
        try await Task.sleep(for: .milliseconds(50))
        #expect(gateway.socket.sent.count == 1)
    }

    // MARK: - The dashboard

    /// The dashboard ends a reply before Hermes judges it, so the goal would look idle for as long
    /// as the judge takes. Its calls and the snapshot's shape are from Hermes's source only.
    @Test func onTheDashboardAGoalWorksWhileItsReplyIsJudged() async throws {
        let gateway = ScriptedGateway()
        gateway.socket.goalControl.withLock { $0 = goal() }
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": true, "messages": .array([])])
        try await waitUntilOnMain { thread.goal != nil }
        func apply(_ type: String, _ payload: JSONValue) {
            thread.apply(GatewayEvent(type: type, sessionID: "live-1", seq: nil, payload: payload))
        }
        #expect(thread.goalPhase == .working)
        apply("message.complete", ["text": "Step one.", "status": "complete"])
        #expect(!thread.state.isRunning)
        #expect(thread.goalPhase == .working)
        #expect(thread.activity == .working)
        apply("session.control.update", ["control": goal(used: 2, check: "More to do.")])
        #expect(thread.goalPhase == .working)
        apply("message.start", [:])
        apply("message.complete", ["text": "Step two.", "status": "complete"])
        apply("session.control.update", ["control": goal("done", used: 3)])
        #expect(thread.goalPhase == .done)
        #expect(thread.activity == .idle)
        // A reply that was stopped isn't judged, so nothing follows it.
        apply("session.control.update", ["control": goal()])
        apply("message.start", [:])
        apply("message.complete", ["text": "", "status": "interrupted"])
        #expect(thread.goalPhase == .notRunning)
    }

    // MARK: - The demo

    @Test func theDemoRunsAGoal() async throws {
        let model = AppModel.demo()
        let ops = try #require(model.contacts.first { $0.id == "ops" })
        let thread = model.thread(for: ops)
        #expect(thread.goal?.status == .active)
        #expect(thread.goalPhase == .working)
        thread.stopGoal()
        #expect(thread.goalPhase == .stopped)
        #expect(thread.goal?.stopReason == .byYou)
        #expect(!thread.state.isRunning)
        thread.clearGoal()
        #expect(thread.goal == nil)
        thread.send("/goal Tidy the runbook")
        #expect(thread.goal == Goal(text: "Tidy the runbook"))
        #expect(thread.goalPhase == .working)
    }
}
