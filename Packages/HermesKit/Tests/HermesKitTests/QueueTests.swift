import Foundation
import Testing

@testable import HermesKit

/// The message queue. The recorded cases play traffic from a throwaway Hermes 0.23.1 gateway
/// (`Fixtures/README.md`); the rest script the gateway's answers.
@MainActor
struct QueueTests {
    private static let ready: JSONValue = [
        "jsonrpc": "2.0", "method": "event",
        "params": ["type": "gateway.ready", "payload": ["session_authority": true, "replay_epoch": "e1"]],
    ]

    /// A chat open on the gateway's own listener, with its events routed to it as `AppModel` does.
    private func open(resume: JSONValue, cached: CachedThread? = nil) async throws
        -> (ChatThread, ScriptedGateway, Task<Void, Never>)
    {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        try gateway.socket.deliver(Self.ready)
        #expect(try await channel.waitUntilReady().dialect == .canonical)
        let thread = ChatThread(contactID: "scout", cached: cached, channel: { channel })
        let events = channel.events
        let routing = Task { @MainActor in for await event in events { thread.apply(event) } }
        thread.open(knownID: "local-chat", dialect: .canonical)
        _ = try await gateway.answer(0, method: "session.resume", result: resume)
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway, routing)
    }

    private func row(_ id: String, _ text: String, _ status: String, controls: Bool = true, steering: Bool = false)
        -> JSONValue
    {
        [
            "admission_id": .string("adm-\(id)"), "input_id": .string(id), "text": .string(text),
            "status": .string(status), "controls": controls ? ["steer", "replace"] : [],
            "steering": .bool(steering),
        ]
    }

    private func info(_ rows: [JSONValue], running: Bool, seq: Int) -> JSONValue {
        [
            "jsonrpc": "2.0", "method": "event",
            "params": [
                "type": "session.info", "session_id": "local-chat", "replay_epoch": "s1", "seq": .number(Double(seq)),
                "payload": ["pending": .array(rows), "running": .bool(running)],
            ],
        ]
    }

    private let idle: JSONValue = ["session_id": "local-chat", "running": false, "display_messages": [], "pending": []]

    private func runningSnapshot(_ rows: [JSONValue]) -> JSONValue {
        [
            // No `replay_epoch`, so attaching doesn't read the reply so far.
            "session_id": "local-chat", "running": true, "execution_generation": 4,
            "display_messages": [["role": "user", "text": "Start"]],
            "pending": .array([row("first", "Start", "started", controls: false)] + rows),
        ]
    }

    /// One step of a recording: wait for `ready`, do `act`, and the app sends the recorded request.
    private struct Step {
        let method: String
        var ready: @MainActor () -> Bool = { true }
        var act: @MainActor () -> Void = {}
    }

    /// Plays a recording through `thread`: each recorded request is a step the test takes,
    /// answered as the gateway answered it, with the events in between in the order they came.
    /// The app's own submission IDs take the recorded ones' place in what the gateway sends back.
    private func play(_ name: String, steps: (ChatThread) -> [Step]) async throws
        -> (ChatThread, ScriptedGateway, Task<Void, Never>)
    {
        let recording = try RecordedGatewayTests.Recording(name)
        let (thread, gateway, routing) = try await open(resume: recording.result(of: "session.resume"))
        var swaps: [String: String] = [:]
        var requestIDs: [JSONValue: JSONValue] = [:]
        var steps = steps(thread)[...]
        let afterResume = try #require(recording.entries.firstIndex { $0.frame["result"]?["display_messages"] != nil })
        for entry in recording.entries[(afterResume + 1)...] {
            if entry.direction == "out" {
                let next = steps.popFirst()
                let step = try #require(next, "The recording has a request the test doesn't make")
                try await waitUntilOnMain(step.ready)
                let sent = gateway.socket.sent.count
                step.act()
                try await waitUntil { gateway.socket.sent.count == sent + 1 }
                let request = gateway.socket.sent[sent]
                #expect(request["method"]?.stringValue == step.method)
                #expect(entry.frame["method"]?.stringValue == step.method)
                #expect(request["params"]?["profile"] == "scout")
                requestIDs[entry.frame["id"] ?? .null] = request["id"]
                if let recorded = entry.frame["params"]?["submission_id"]?.stringValue {
                    swaps[recorded] = try #require(request["params"]?["submission_id"]?.stringValue)
                } else {
                    // Everything else names what the gateway named: the same admission, the same turn.
                    #expect(request["params"]?["admission_id"] == entry.frame["params"]?["admission_id"])
                    #expect(
                        request["params"]?["execution_generation"] == entry.frame["params"]?["execution_generation"])
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
            gateway.socket.deliver(text)
        }
        #expect(steps.isEmpty)
        return (thread, gateway, routing)
    }

    // MARK: - Recorded

    @Test func queuedMessagesWaitOnTheGatewayAndGoOutByThemselves() async throws {
        let (played, gateway, routing) = try await play("canonical-queue") { thread in
            [
                Step(method: "prompt.submit", act: { thread.send("slow A") }),
                Step(method: "prompt.submit", act: { thread.enqueue("slow B") }),
                Step(method: "prompt.submit", act: { thread.enqueue("C") }),
                Step(
                    method: "prompt.cancel",
                    ready: { thread.queue.map(\.text) == ["slow B", "C"] && !thread.queue.contains { $0.isSending } },
                    act: {
                        // Your own message isn't listed as queued, though the gateway lists it so.
                        #expect(thread.state.items.map(\.content) == [.user("slow A")])
                        thread.remove(thread.queue[1])
                    }),
            ]
        }
        defer { routing.cancel() }
        try await waitUntilOnMain { !played.state.isRunning && played.state.items.count == 4 }
        #expect(
            played.state.items.map(\.content) == [
                .user("slow A"), .assistant("ECHO: slow A"), .user("slow B"), .assistant("ECHO: slow B"),
            ])
        #expect(played.queue.isEmpty)
        // No `session.history` read: the queued message's text was already here when its turn began.
        #expect(gateway.socket.sent.count == 5)
    }

    @Test func stopHoldsWhatIsQueuedInsteadOfStartingIt() async throws {
        let (played, gateway, routing) = try await play("canonical-queue-stop") { thread in
            [
                Step(method: "prompt.submit", act: { thread.send("slow H") }),
                Step(method: "prompt.submit", act: { thread.enqueue("slow I") }),
                Step(
                    method: "prompt.cancel", ready: { thread.queue.count == 1 && !thread.queue[0].isSending },
                    act: { thread.stop() }),
                // Sent by itself once the queued message is back.
                Step(method: "session.interrupt"),
            ]
        }
        defer { routing.cancel() }
        try await waitUntilOnMain { !played.state.isRunning }
        #expect(played.queue.map(\.text) == ["slow I"])
        #expect(played.queue.first?.isHeld == true)
        #expect(played.holdsQueue)
        #expect(!played.state.items.contains { $0.content == .user("slow I") })
        // Kept across a relaunch.
        #expect(played.cacheEntry.heldMessages?.map(\.text) == ["slow I"])

        // Resuming queues it again as a new message: the gateway knows the old ID as cancelled.
        let before = gateway.socket.sent.compactMap { $0["params"]?["submission_id"]?.stringValue }
        played.resumeQueue()
        let resumed = try await gateway.answer(
            5, method: "prompt.submit", result: ["admission_id": "adm-new", "status": "queued"])
        #expect(resumed["text"] == "slow I")
        #expect(!before.contains(try #require(resumed["submission_id"]?.stringValue)))
        try await waitUntilOnMain { played.queue.first?.isHeld == false && played.queue.first?.isSending == false }
    }

    // MARK: - Scripted

    @Test func theDashboardHasNoQueueSoAMessageSteers() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "scout", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": true, "messages": []])
        try await waitUntilOnMain { thread.isAttached }
        #expect(!thread.canQueue)

        thread.enqueue("Use the staging database")
        let steered = try await gateway.answer(1, method: "session.steer", result: ["status": "queued"])
        #expect(steered["text"] == "Use the staging database")
        #expect(thread.queue.isEmpty)
    }

    @Test func aMessageQueuedBeforeYouAttachedShowsAndStartsOnce() async throws {
        let (thread, gateway, routing) = try await open(resume: runningSnapshot([row("q1", "Then the logs", "queued")]))
        defer { routing.cancel() }
        #expect(thread.queue.map(\.text) == ["Then the logs"])
        #expect(thread.canQueue)

        // The reply ends, and the gateway starts the queued message.
        for (type, payload, seq) in [
            ("message.complete", ["status": "complete", "text": "Done"] as JSONValue, 10),
            ("message.start", [:], 11),
        ] {
            try gateway.socket.deliver([
                "jsonrpc": "2.0", "method": "event",
                "params": [
                    "type": .string(type), "session_id": "local-chat", "replay_epoch": "s1",
                    "seq": .number(Double(seq)), "execution_generation": 5, "payload": payload,
                ],
            ])
        }
        try gateway.socket.deliver(
            info([row("q1", "Then the logs", "started", controls: false)], running: true, seq: 12))
        try await waitUntilOnMain { thread.queue.isEmpty }
        #expect(thread.state.items.map(\.content) == [.user("Start"), .assistant("Done"), .user("Then the logs")])
        #expect(thread.state.isRunning)
    }

    @Test func onlyTypedMessagesBehindAReplyAreListedFromOtherApps() async throws {
        let (thread, gateway, routing) = try await open(resume: idle)
        defer { routing.cancel() }
        // Sent from another app into an idle chat: listed as queued for a moment, then it starts.
        try gateway.socket.deliver(info([row("other", "Hello", "queued")], running: false, seq: 1))
        // A routine's result waiting behind a reply has no queue controls.
        try gateway.socket.deliver(info([row("cron", "Report", "queued", controls: false)], running: true, seq: 2))
        // One being steered into the reply is listed as started.
        try gateway.socket.deliver(info([row("steer", "Faster", "started", steering: true)], running: true, seq: 3))
        try gateway.socket.deliver(info([row("theirs", "After this", "queued")], running: true, seq: 4))
        try await waitUntilOnMain { !thread.queue.isEmpty }
        #expect(thread.queue.map(\.text) == ["After this"])
        #expect(thread.state.items.isEmpty)
    }

    @Test func aMessageTheGatewayCouldNotTakeIsHeldAndRetriedUnderTheSameID() async throws {
        let (thread, gateway, routing) = try await open(resume: runningSnapshot([]))
        defer { routing.cancel() }
        thread.enqueue("Then the logs")
        let first = try await gateway.answer(1, method: "prompt.submit", error: (-32000, "timed out"))
        try await waitUntilOnMain { thread.holdsQueue }
        #expect(thread.queue.map(\.text) == ["Then the logs"])
        guard case .notice(let notice) = thread.state.items.last?.content else {
            Issue.record("Expected a notice")
            return
        }
        #expect(notice.hasPrefix("Couldn't queue your message, so it's held here"))

        // The gateway had taken it after all: the same ID gets the first receipt, not a second message.
        thread.resumeQueue()
        let second = try await gateway.answer(
            2, method: "prompt.submit", result: ["admission_id": "adm-1", "status": "queued"])
        #expect(second["submission_id"] == first["submission_id"])
        try await waitUntilOnMain { thread.queue.first?.isSending == false && !thread.holdsQueue }
    }

    @Test func sendNowTakesItBackThenSteersTheReply() async throws {
        let (thread, gateway, routing) = try await open(
            resume: runningSnapshot([row("q1", "Skip the tests", "queued")]))
        defer { routing.cancel() }
        thread.sendNow(try #require(thread.queue.first))
        let cancelled = try await gateway.answer(
            1, method: "prompt.cancel", result: ["status": "terminal", "outcome": "cancelled"])
        #expect(cancelled["admission_id"] == "adm-q1")
        let steered = try await gateway.answer(2, method: "session.steer", result: ["status": "queued"])
        #expect(steered["text"] == "Skip the tests")
        #expect(steered["execution_generation"] == 4)
        #expect(thread.queue.isEmpty)
        #expect(thread.state.items.last?.content == .user("Skip the tests"))
        // The gateway's list a moment later still has it; it doesn't come back.
        try gateway.socket.deliver(info([row("q1", "Skip the tests", "queued")], running: true, seq: 20))
        try gateway.socket.deliver(info([], running: true, seq: 21))
        try await waitUntil { gateway.socket.sent.count == 3 }
        #expect(thread.queue.isEmpty)
    }

    @Test func editPutsAQueuedMessageBackInTheBox() async throws {
        let (thread, gateway, routing) = try await open(
            resume: runningSnapshot([row("q1", "Skip the tests", "queued")]))
        defer { routing.cancel() }
        thread.edit(try #require(thread.queue.first))
        _ = try await gateway.answer(
            1, method: "prompt.cancel", result: ["status": "terminal", "outcome": "cancelled"])
        try await waitUntilOnMain { thread.prefill == "Skip the tests" }
        #expect(thread.queue.isEmpty)
    }

    @Test func takingBackAMessageThatHadStartedSaysItsReplyWasStopped() async throws {
        let (thread, gateway, routing) = try await open(
            resume: runningSnapshot([row("q1", "Skip the tests", "queued")]))
        defer { routing.cancel() }
        thread.edit(try #require(thread.queue.first))
        // The gateway stops a started message in the same call, and its receipt reads `started`.
        _ = try await gateway.answer(1, method: "prompt.cancel", result: ["status": "started", "outcome": .null])
        try await waitUntilOnMain { thread.queue.isEmpty && thread.state.items.count == 3 }
        #expect(
            thread.state.items.suffix(2).map(\.content) == [
                .user("Skip the tests"), .notice("That message had already started, so its reply was stopped."),
            ])
        #expect(thread.prefill == nil)
    }

    @Test func aRefusedTakeBackLeavesTheMessageQueued() async throws {
        let (thread, gateway, routing) = try await open(
            resume: runningSnapshot([row("q1", "Skip the tests", "queued")]))
        defer { routing.cancel() }
        thread.remove(try #require(thread.queue.first))
        _ = try await gateway.answer(1, method: "prompt.cancel", error: (-32000, "storage_unavailable"))
        try await waitUntilOnMain { thread.queue.count == 1 && thread.state.items.count == 2 }
        #expect(thread.queue.map(\.text) == ["Skip the tests"])
    }

    @Test func heldMessagesComeBackAfterARelaunch() async throws {
        var cached = CachedThread(state: ThreadState(), lastViewed: nil, unreadCount: 0)
        cached.heldMessages = [QueuedMessage(id: "held-1", text: "Then the logs", isHeld: true)]
        let restored = try JSONDecoder().decode(CachedThread.self, from: JSONEncoder().encode(cached))
        let (thread, gateway, routing) = try await open(resume: idle, cached: restored)
        defer { routing.cancel() }
        #expect(thread.queue.map(\.text) == ["Then the logs"])
        #expect(thread.holdsQueue)

        // Held on this device only: removing it asks the gateway nothing.
        thread.sendNow(try #require(thread.queue.first))
        let sent = try await gateway.answer(1, method: "prompt.submit", result: ["status": "queued"])
        #expect(sent["text"] == "Then the logs")
        #expect(thread.queue.isEmpty)
        #expect(thread.state.items.map(\.content) == [.user("Then the logs")])
    }

    @Test func aSteerThatArrivedTooLateGoesAsATurnNotIntoTheQueue() async throws {
        let (thread, gateway, routing) = try await open(resume: runningSnapshot([]))
        defer { routing.cancel() }
        thread.send("One more thing")
        _ = try await gateway.answer(
            1, method: "session.steer", result: ["status": "rejected", "delivered": false, "text": "One more thing"])
        let submitted = try await gateway.answer(2, method: "prompt.submit", result: ["status": "queued"])
        let id = try #require(submitted["submission_id"]?.stringValue)
        // The gateway lists it as queued behind the reply that's still ending. It's already shown as sent.
        try gateway.socket.deliver(info([row(id, "One more thing", "queued")], running: true, seq: 30))
        try gateway.socket.deliver(
            info([row(id, "One more thing", "started", controls: false)], running: true, seq: 31))
        try gateway.socket.deliver(info([row("theirs", "After this", "queued")], running: true, seq: 32))
        try await waitUntilOnMain { !thread.queue.isEmpty }
        #expect(thread.queue.map(\.text) == ["After this"])
        #expect(thread.state.items.filter { $0.content == .user("One more thing") }.count == 1)
    }

    @Test func aCommandIsNotQueued() async throws {
        let (thread, gateway, routing) = try await open(resume: runningSnapshot([]))
        defer { routing.cancel() }
        thread.enqueue("/btw how long is this taking?")
        _ = try await gateway.answer(1, method: "prompt.btw", result: [:])
        #expect(thread.queue.isEmpty)
    }

    @Test func aSteeredQueuedMessageEndsNoTurn() {
        var canonical = CanonicalProtocol()
        let frame: JSONValue = [
            "type": "message.complete", "session_id": "local-chat", "admission_id": "adm-q1",
            "payload": ["text": "", "content": "", "admission_id": "adm-q1", "outcome": "steered"],
        ]
        #expect(canonical.inbound(frame).isEmpty)
    }

    #if DEBUG
        @Test func theDemoQueuesSendsNowAndHoldsOnStop() async throws {
            let model = AppModel.demo()
            let ops = try #require(model.contacts.first { $0.id == "ops" })
            let thread = model.thread(for: ops)
            #expect(thread.queue.count == 2)
            #expect(thread.canQueue)

            thread.enqueue("And db-3 after that.")
            #expect(thread.queue.map(\.text).last == "And db-3 after that.")
            thread.sendNow(thread.queue[0])
            try await waitUntilOnMain { thread.queue.count == 2 }
            #expect(thread.state.items.last?.content == .user("Then check the same on db-2."))

            thread.stop()
            #expect(!thread.state.isRunning)
            #expect(thread.queue.count == 2)
            #expect(thread.queue.allSatisfy { $0.isHeld })

            // Resuming sends the first, and the next waits for its reply.
            thread.resumeQueue()
            #expect(thread.state.isRunning)
            #expect(thread.queue.count == 1)
            #expect(!thread.holdsQueue)
        }
    #endif
}
