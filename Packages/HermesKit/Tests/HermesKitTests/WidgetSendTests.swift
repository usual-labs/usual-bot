import Foundation
import Testing

@testable import HermesKit

/// Inline widgets talking back (`window.hermes.send`): a hidden turn that never shows as yours.
@MainActor
struct WidgetSendTests {
    private static let prompt = "Clear logs older than two weeks on db-1, then update this widget."

    private static let ready: JSONValue = [
        "jsonrpc": "2.0", "method": "event",
        "params": ["type": "gateway.ready", "payload": ["session_authority": true, "replay_epoch": "e1"]],
    ]

    /// A chat open on the gateway's own listener (`canonical`) or the dashboard, with its events
    /// routed to it as `AppModel` does.
    private func open(canonical: Bool, running: Bool) async throws -> (ChatThread, ScriptedGateway, Task<Void, Never>) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        if canonical { try gateway.socket.deliver(Self.ready) }
        let thread = ChatThread(contactID: "ops", channel: { channel })
        let events = channel.events
        let routing = Task { @MainActor in for await event in events { thread.apply(event) } }
        thread.open(knownID: "local-chat", dialect: canonical ? .canonical : .legacy)
        let started: JSONValue = [
            "admission_id": "adm-first", "input_id": "first", "text": "Show me disk use", "status": "started",
            "controls": [], "steering": false,
        ]
        _ = try await gateway.answer(
            0, method: "session.resume",
            result: [
                "session_id": "local-chat", "running": .bool(running), "execution_generation": 4,
                "display_messages": [["role": "user", "text": "Show me disk use"]],
                "messages": [["role": "user", "text": "Show me disk use"]],
                "pending": running ? [started] : [],
            ])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway, routing)
    }

    /// Answers the first request for `method` the app sends.
    private func answer(
        _ gateway: ScriptedGateway, _ method: String, result: JSONValue? = nil, error: (Int, String)? = nil
    )
        async throws -> JSONValue
    {
        try await waitUntil { gateway.socket.sent.contains { $0["method"]?.stringValue == method } }
        let index = try #require(gateway.socket.sent.firstIndex { $0["method"]?.stringValue == method })
        return try await gateway.answer(index, method: method, result: result, error: error)
    }

    private func event(_ type: String, _ payload: JSONValue) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "local-chat", seq: nil, payload: payload)
    }

    // MARK: - Sending

    @Test func anIdleChatTakesItAsAHiddenTurn() async throws {
        let (thread, gateway, routing) = try await open(canonical: true, running: false)
        defer { routing.cancel() }
        let items = thread.state.items

        async let ack = thread.sendFromWidget(Self.prompt)
        let params = try await answer(gateway, "prompt.submit", result: ["status": "queued", "admission_id": "adm-2"])

        #expect(params["display_kind"] == "hidden")
        #expect(params["text"]?.stringValue == Self.prompt)
        #expect(params["submission_id"]?.stringValue?.isEmpty == false)
        #expect(await ack == .sent)
        #expect(thread.state.items == items)
        #expect(thread.state.isRunning)
        #expect(thread.queue.isEmpty)
    }

    @Test func behindARunningReplyItWaitsInTheQueueAsFromAWidget() async throws {
        let (thread, gateway, routing) = try await open(canonical: true, running: true)
        defer { routing.cancel() }
        let items = thread.state.items

        async let ack = thread.sendFromWidget(Self.prompt)
        let params = try await answer(gateway, "prompt.submit", result: ["status": "queued", "admission_id": "adm-2"])
        #expect(await ack == .sent)
        #expect(params["display_kind"] == "hidden")
        #expect(gateway.socket.sent.allSatisfy { $0["method"] != "session.steer" })
        let queued = try #require(thread.queue.first)
        #expect(queued.isFromWidget)
        #expect(queued.admissionID == "adm-2")

        // The reply ends and the widget's turn starts: it shows nothing of its own.
        thread.apply(event("message.complete", ["status": "complete", "text": "Disk use is fine."]))
        let id = try #require(params["submission_id"]?.stringValue)
        thread.apply(
            event(
                "session.info",
                [
                    "running": true,
                    "pending": [
                        [
                            "admission_id": "adm-2", "input_id": .string(id), "text": .string(Self.prompt),
                            "status": "started", "controls": [], "steering": false,
                        ]
                    ],
                ]))
        #expect(thread.queue.isEmpty)
        #expect(!thread.state.items.contains { $0.content == .user(Self.prompt) })
        #expect(thread.state.items.count == items.count + 1)
    }

    @Test func theDashboardRefusesItWhileAReplyRuns() async throws {
        let (thread, gateway, routing) = try await open(canonical: false, running: true)
        defer { routing.cancel() }

        let ack = await thread.sendFromWidget(Self.prompt)

        #expect(ack.failure == .undelivered)
        #expect(ack.reason == .busy)
        #expect(gateway.socket.sent.count == 1)
        #expect(thread.queue.isEmpty)
    }

    @Test func offlineItsRefusedAtOnce() async {
        let thread = ChatThread(contactID: "ops", channel: { nil })

        let ack = await thread.sendFromWidget(Self.prompt)

        #expect(ack.failure == .undelivered)
        #expect(ack.reason == .offline)
        #expect(ack.object["error"] as? String == "undelivered")
        #expect(ack.object["ok"] as? Bool == false)
    }

    @Test func aRefusalReachesTheWidgetAndEndsTheTurn() async throws {
        let (thread, gateway, routing) = try await open(canonical: false, running: false)
        defer { routing.cancel() }

        async let ack = thread.sendFromWidget(Self.prompt)
        _ = try await answer(gateway, "prompt.submit", error: (4009, "session busy"))

        let answered = await ack
        #expect(answered.failure == .undelivered)
        #expect(answered.reason == .refused)
        #expect(!thread.state.isRunning)
    }

    @Test func stoppingDropsAQueuedWidgetPromptInsteadOfHoldingIt() async throws {
        let (thread, gateway, routing) = try await open(canonical: true, running: true)
        defer { routing.cancel() }
        async let ack = thread.sendFromWidget(Self.prompt)
        _ = try await answer(gateway, "prompt.submit", result: ["status": "queued", "admission_id": "adm-2"])
        _ = await ack

        thread.stop()
        _ = try await answer(gateway, "prompt.cancel", result: ["status": "terminal", "outcome": "cancelled"])

        try await waitUntilOnMain { thread.queue.isEmpty }
        #expect(!thread.holdsQueue)
    }

    // MARK: - Its reply

    @Test func itsReplyDoesntAlertButCountsAsATurnEnded() async throws {
        let (thread, gateway, routing) = try await open(canonical: false, running: false)
        defer { routing.cancel() }
        var alerts: [AgentAlert] = []
        thread.alert = { alerts.append($0) }
        async let ack = thread.sendFromWidget(Self.prompt)
        _ = try await answer(gateway, "prompt.submit")
        _ = await ack

        thread.apply(event("message.delta", ["text": "Cleared 14 GB."]))
        thread.apply(event("message.complete", ["status": "complete"]))

        #expect(alerts.isEmpty)
        #expect(thread.turnsEnded == 1)
        #expect(thread.state.items.last?.content == .assistant("Cleared 14 GB."))

        // A message of yours alerts as before.
        thread.send("Thanks")
        _ = try await gateway.answer(2, method: "prompt.submit")
        thread.apply(event("message.delta", ["text": "Any time."]))
        thread.apply(event("message.complete", ["status": "complete"]))
        #expect(alerts.count == 1)
        #expect(thread.turnsEnded == 2)
    }

    // MARK: - The chat list

    @Test func aHiddenPromptAsTheRostersPreviewGivesWayToTheChat() {
        let long = Self.prompt + " Then check web-1 and web-2 the same way, and say what you freed."
        let state = ThreadState(
            history: [
                HistoryMessage(role: "assistant", text: "Here's disk use."),
                HistoryMessage(role: "user", text: long, displayKind: "hidden"),
            ], running: false)
        let cut = String(long.prefix(80)) + "..."

        #expect(state.isHiddenPreview(Contact.plainPreview(cut)))
        #expect(!state.isHiddenPreview("Here's disk use."))
    }

    // MARK: - The gate

    /// The gate with a tap a moment ago, none spent.
    private func gate(
        _ body: Any?, now: ContinuousClock.Instant, tappedAt: ContinuousClock.Instant?? = .none,
        spentTap: ContinuousClock.Instant? = nil, lastAccepted: ContinuousClock.Instant? = nil
    ) -> Result<String, WidgetIntentRefusal> {
        WidgetIntent.evaluate(
            body, now: now, tappedAt: tappedAt ?? now - .milliseconds(100), spentTap: spentTap,
            lastAccepted: lastAccepted)
    }

    @Test func theGateTrimsRefusesAndSlowsDown() throws {
        let now = ContinuousClock.now
        #expect(try gate("  Refresh  ", now: now).get() == "Refresh")
        #expect(gate("   ", now: now) == .failure(.init(ack: .init(failure: .invalid))))
        #expect(gate(42, now: now) == .failure(.init(ack: .init(failure: .invalid))))
        #expect(
            gate(String(repeating: "a", count: 501), now: now)
                == .failure(.init(ack: .init(failure: .tooLong, maxLength: 500))))
        #expect((try? gate(String(repeating: "a", count: 500), now: now).get()) != nil)

        let throttled = gate("Refresh", now: now, lastAccepted: now - .milliseconds(400))
        guard case .failure(let refusal) = throttled else {
            Issue.record("A second prompt within a second went through")
            return
        }
        #expect(refusal.ack.failure == .throttled)
        #expect(refusal.ack.retryAfterMilliseconds == 600)
        #expect((try? gate("Refresh", now: now, lastAccepted: now - .seconds(1)).get()) == "Refresh")
    }

    @Test func aSendNeedsATapInTheLastThreeSeconds() {
        let now = ContinuousClock.now
        // A page's script on its own: a timer, or `el.click()`.
        let untapped = gate("Refresh", now: now, tappedAt: .some(nil))
        guard case .failure(let refusal) = untapped else {
            Issue.record("A send with no tap went through")
            return
        }
        #expect(refusal.ack.failure == .undelivered)
        #expect(refusal.ack.reason == .needsTap)
        #expect(refusal.ack.object["reason"] as? String == "needs_tap")
        #expect(refusal.ack.message?.isEmpty == false)

        #expect((try? gate("Refresh", now: now, tappedAt: now - .seconds(3)).get()) == "Refresh")
        #expect((try? gate("Refresh", now: now, tappedAt: now - .milliseconds(3001)).get()) == nil)
    }

    @Test func aTapSendsOnce() {
        let now = ContinuousClock.now
        let tap = now - .milliseconds(1500)
        // A script that waits for your click and sends twice gets the second refused.
        let again = gate("Refresh", now: now, tappedAt: tap, spentTap: tap, lastAccepted: now - .seconds(2))
        guard case .failure(let refusal) = again else {
            Issue.record("One tap sent twice")
            return
        }
        #expect(refusal.ack.reason == .needsTap)
        #expect((try? gate("Refresh", now: now, tappedAt: now, spentTap: tap).get()) == "Refresh")
    }
}
