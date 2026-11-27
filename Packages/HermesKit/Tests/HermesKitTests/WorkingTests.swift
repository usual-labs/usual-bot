import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// When a Bot counts as working: a reply, and the work that goes on after it.
@MainActor
struct WorkingTests {
    private func event(_ type: String, _ payload: JSONValue = [:]) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "live-1", seq: nil, payload: payload)
    }

    private func idleThread() -> ChatThread {
        ChatThread.sample("forge", state: ThreadState(history: [], running: false))
    }

    @Test func workOnTheSideCountsAsWorking() {
        let thread = idleThread()
        #expect(thread.activity == .idle)

        thread.backgroundTasks = [BackgroundTask(id: "bg_1", task: "watch the PR")]
        #expect(thread.activity == .working)
        thread.backgroundTasks = []

        thread.sideQuestions = [SideQuestion(id: "btw_1", question: "which branch?", answer: .waiting)]
        #expect(thread.activity == .working)
        thread.sideQuestions = [SideQuestion(id: "btw_1", question: "which branch?", answer: .answered("main"))]
        #expect(thread.activity == .idle)

        thread.isCompressing = true
        #expect(thread.activity == .working)
        thread.isCompressing = false

        thread.runningProcesses = ["proc_1"]
        #expect(thread.activity == .working)
    }

    @Test func aHelperThatOutlivesItsTurnKeepsTheBotWorking() {
        let thread = idleThread()
        thread.state.sendLocally("review the release")
        thread.apply(event("subagent.start", ["subagent_id": "a", "goal": "Read the logs"]))
        thread.apply(event("message.complete", ["status": "complete", "text": "Started a helper."]))
        #expect(!thread.state.isRunning)
        #expect(thread.activity == .working)

        thread.apply(event("subagent.complete", ["subagent_id": "a", "status": "completed"]))
        #expect(thread.activity == .idle)
    }

    @Test func needingYouWinsOverWorking() {
        let thread = idleThread()
        thread.runningProcesses = ["proc_1"]
        thread.receive(
            ApprovalPrompt(id: "a1", sessionID: "sample", command: "git push", description: "push", choices: []))
        #expect(thread.activity == .needsYou)
    }

    @Test func aProcessLeftRunningIsFollowedUntilItEnds() async throws {
        let gateway = ScriptedGateway()
        gateway.socket.processes.withLock {
            $0 = [
                ["session_id": "proc_1", "command": "gh pr checks --watch", "status": "running"],
                ["session_id": "proc_0", "command": "ls", "status": "exited", "exit_code": 0],
            ]
        }
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "forge", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.runningProcesses == ["proc_1"] }
        #expect(thread.activity == .working)

        // The process ends and Hermes tells the agent, which replies.
        gateway.socket.processes.withLock {
            $0 = [["session_id": "proc_1", "command": "gh pr checks --watch", "status": "exited", "exit_code": 0]]
        }
        thread.apply(event("message.start"))
        thread.apply(event("message.complete", ["status": "complete", "text": "The checks passed."]))
        try await waitUntilOnMain { thread.runningProcesses.isEmpty }
        #expect(thread.activity == .idle)
    }

    @Test func aGatewayWithoutProcessesLeavesTheChatIdle() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "forge", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": .array([])])
        try await waitUntil { gateway.socket.processReads.withLock { $0 } == 1 }
        try await waitUntilOnMain { thread.processCheck != nil }
        await thread.processCheck?.value
        #expect(thread.activity == .idle)
    }

    @Test func theProcessListGoesToTheBotsProfile() {
        var canonical = CanonicalProtocol()
        canonical.update("local-1") { $0.profile = "forge" }
        #expect(canonical.routed("process.list", ["session_id": "local-1"])["profile"] == "forge")
    }
}

/// A routine runs in a session of its own; the jobs list says while it does.
@MainActor
struct RunningRoutinesTests {
    private func job(_ id: String, profile: String, live: Bool) -> JSONValue {
        [
            "id": .string(id), "profile": .string(profile),
            "live_execution": live ? ["id": "exec-1", "status": "running"] : .null,
        ]
    }

    @Test func aBotWithALiveRunIsWorking() {
        let routines = RunningRoutines { [] }
        routines.adopt([
            job("digest", profile: "default", live: true), job("backup", profile: "forge", live: false),
            job("sweep", profile: "scribe", live: true),
        ])
        #expect(routines.profiles == ["default", "scribe"])
        // A gateway older than `live_execution` never says a run is live.
        routines.adopt([["id": "digest", "profile": "default"]])
        #expect(routines.profiles.isEmpty)
    }

    @Test func theListIsReadEveryMinuteAndMoreOftenWhileSomethingRuns() async throws {
        let reads = Mutex(0)
        let answer = Mutex<JSONValue>([])
        let routines = RunningRoutines {
            reads.withLock { $0 += 1 }
            return answer.withLock { $0 }
        }
        let start = ContinuousClock.now
        routines.readIfDue(now: start)
        try await waitUntil { reads.withLock { $0 } == 1 }
        routines.readIfDue(now: .now + .seconds(30))
        #expect(reads.withLock { $0 } == 1)

        answer.withLock { $0 = [self.job("digest", profile: "forge", live: true)] }
        routines.readIfDue(now: .now + .seconds(61))
        try await waitUntilOnMain { routines.profiles == ["forge"] }
        // Running, it's read again after 15 s, to see the run end.
        answer.withLock { $0 = [] }
        routines.readIfDue(now: .now + .seconds(16))
        try await waitUntilOnMain { routines.profiles.isEmpty }
        #expect(reads.withLock { $0 } == 3)
    }

    @Test func theSidebarShowsABotWorkingWhileItsRoutineRuns() {
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        model.contacts = [
            Contact(id: "forge", name: "Forge"), Contact(id: "scribe", name: "Scribe"),
            Contact(id: "atlas", name: "Atlas"),
        ]
        let waiting = ChatThread.sample("scribe", state: ThreadState(history: [], running: false))
        waiting.receive(
            ApprovalPrompt(id: "a1", sessionID: "sample", command: "rm -rf build", description: "clean", choices: []))
        model.threads["scribe"] = waiting
        model.runningRoutines.adopt([
            job("digest", profile: "forge", live: true), job("notes", profile: "scribe", live: true),
        ])
        let activity = Dictionary(uniqueKeysWithValues: model.sidebarContacts.map { ($0.id, $0.activity) })
        #expect(activity == ["forge": .working, "scribe": .needsYou, "atlas": .idle])
    }
}
