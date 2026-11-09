import Foundation
import Testing

@testable import HermesKit

extension RecordedGatewayTests.Recording {
    /// The `result` the gateway gave the `occurrence`th call of `method`.
    func result(of method: String, occurrence: Int = 0) throws -> JSONValue {
        let calls = entries.filter { $0.direction == "out" && $0.frame["method"]?.stringValue == method }
        let id = try #require(calls.dropFirst(occurrence).first?.frame["id"])
        let reply = try #require(
            entries.first { $0.direction == "in" && $0.frame["id"] == id && $0.frame["method"] == nil })
        return reply.frame["result"] ?? .null
    }

    /// What the probe that recorded this sent for `method`.
    func params(of method: String) throws -> JSONValue {
        try #require(
            entries.first { $0.direction == "out" && $0.frame["method"]?.stringValue == method }?.frame["params"])
    }

    /// The events after the reply to `method`'s first call, in order.
    func events(after method: String) throws -> [JSONValue] {
        let id = try #require(
            entries.first { $0.direction == "out" && $0.frame["method"]?.stringValue == method }?.frame["id"])
        let reply = try #require(
            entries.firstIndex { $0.direction == "in" && $0.frame["id"] == id && $0.frame["method"] == nil })
        return entries[(reply + 1)...].filter { $0.direction == "in" && $0.frame["method"] == "event" }.map(\.frame)
    }

    var ready: JSONValue? { inbound.first { $0["params"]?["type"] == "gateway.ready" } }
}

extension FakeSocket {
    func deliver(_ frame: JSONValue) throws {
        deliver(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
    }
}

/// Usual Bot on the gateway's own listener, played from traffic recorded on a throwaway Hermes
/// gateway (anonymised; see `Fixtures/README.md`), and the calls only the canonical protocol makes.
@MainActor
struct CanonicalGatewayTests {
    private func connect(_ recording: RecordedGatewayTests.Recording) async throws -> (JSONRPCChannel, ScriptedGateway)
    {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        try gateway.socket.deliver(try #require(recording.ready))
        #expect(try await channel.waitUntilReady().dialect == .canonical)
        return (channel, gateway)
    }

    /// Hands the channel's events and requests to `thread`, as `AppModel` does.
    private func route(_ channel: JSONRPCChannel, to thread: ChatThread) -> [Task<Void, Never>] {
        let events = channel.events
        let requests = channel.requests
        return [
            Task { @MainActor in for await event in events { thread.apply(event) } },
            Task { @MainActor in
                for await request in requests {
                    if let approval = ApprovalPrompt(request) { thread.receive(approval) }
                    if let prompt = ClarifyPrompt(request) { thread.receive(prompt) }
                }
            },
        ]
    }

    @Test func aBotChatIsMadeAndAReplyStreamsIntoIt() async throws {
        let recording = try RecordedGatewayTests.Recording("canonical-chat-turn")
        let (channel, gateway) = try await connect(recording)
        let thread = ChatThread(contactID: "scout", channel: { channel })
        let routing = route(channel, to: thread)
        defer { routing.forEach { $0.cancel() } }

        thread.open(knownID: nil, dialect: .canonical)
        #expect(
            try await gateway.answer(0, method: "session.list", result: recording.result(of: "session.list"))
                == ["profile": "scout", "title": "Bot Chat", "include_hidden": true])
        let created = try await gateway.answer(
            1, method: "session.create", result: recording.result(of: "session.create"))
        // Titled as it's made, from Hermes's own terminal so its replies notify, and retried safely.
        #expect(created["title"] == "Bot Chat")
        #expect(created["hidden"] == true)
        #expect(created["source"] == "tui")
        #expect(created["request_id"]?.stringValue?.isEmpty == false)
        let resumed = try await gateway.answer(
            2, method: "session.resume", result: recording.result(of: "session.resume"))
        #expect(resumed["display_projection"] == true)
        try await waitUntilOnMain { thread.isAttached }

        let question = try #require(recording.params(of: "prompt.submit")["text"]?.stringValue)
        thread.send(question)
        let submitted = try await gateway.answer(
            3, method: "prompt.submit", result: recording.result(of: "prompt.submit"))
        #expect(submitted["profile"] == "scout")
        #expect(submitted["submission_id"]?.stringValue?.isEmpty == false)
        for frame in try recording.events(after: "prompt.submit") { try gateway.socket.deliver(frame) }
        try await waitUntilOnMain { !thread.state.isRunning }

        #expect(thread.state.items.map(\.content) == [.user(question), .assistant("ECHO: \(question)")])
        #expect(thread.usage?.input == 10)
    }

    @Test func anApprovalAskedAsAnEventIsAnsweredOnTheGateway() async throws {
        let recording = try RecordedGatewayTests.Recording("canonical-approval")
        let (channel, gateway) = try await connect(recording)
        let thread = ChatThread(contactID: "scout", channel: { channel })
        let routing = route(channel, to: thread)
        defer { routing.forEach { $0.cancel() } }

        thread.open(knownID: "local-chat", dialect: .canonical)
        _ = try await gateway.answer(0, method: "session.resume", result: recording.result(of: "session.resume"))
        try await waitUntilOnMain { thread.isAttached }
        let question = try #require(recording.params(of: "prompt.submit")["text"]?.stringValue)
        thread.send(question)
        _ = try await gateway.answer(1, method: "prompt.submit", result: recording.result(of: "prompt.submit"))

        let events = try recording.events(after: "prompt.submit")
        let asking = try #require(events.firstIndex { $0["params"]?["type"] == "approval.request" })
        for frame in events[...asking] { try gateway.socket.deliver(frame) }
        try await waitUntilOnMain { !thread.approvals.isEmpty }
        let approval = try #require(thread.approvals.first)
        #expect(approval.command == "rm -rf /tmp/usualbot-fixture-none")
        #expect(thread.activity == .needsYou)

        thread.answer(approval, with: .deny)
        try await waitUntil { gateway.socket.sent.count == 3 }
        // Exactly what the gateway took when this was recorded: no reply-to-request frame.
        #expect(gateway.socket.sent[2]["method"] == "approval.respond")
        #expect(gateway.socket.sent[2]["params"] == (try recording.params(of: "approval.respond")))
        _ = try await gateway.answer(2, method: "approval.respond", result: recording.result(of: "approval.respond"))

        for frame in events[(asking + 1)...] { try gateway.socket.deliver(frame) }
        try await waitUntilOnMain { !thread.state.isRunning }
        #expect(thread.approvals.isEmpty)
        #expect(thread.state.items.contains { $0.content == .notice("You denied “rm -rf /tmp/usualbot-fixture-none”") })
        // Streamed after the tool, so it starts on a new paragraph.
        guard case .assistant(let reply) = thread.state.items.last?.content else {
            Issue.record("Expected the reply, got \(thread.state.items.map(\.content))")
            return
        }
        #expect(reply.trimmingCharacters(in: .whitespacesAndNewlines) == "APPROVED_DONE")
    }

    /// The reason for the canonical protocol: on it, a routine's result reaches the open Bot Chat.
    @Test func aRoutineResultArrivesInTheOpenChat() async throws {
        let recording = try RecordedGatewayTests.Recording("canonical-routine-delivery")
        let (channel, gateway) = try await connect(recording)
        let thread = ChatThread(contactID: "scout", channel: { channel })
        let routing = route(channel, to: thread)
        defer { routing.forEach { $0.cancel() } }

        thread.open(knownID: "local-chat", dialect: .canonical)
        _ = try await gateway.answer(0, method: "session.resume", result: recording.result(of: "session.resume"))
        try await waitUntilOnMain { thread.isAttached }
        let before = thread.state.items.count

        for frame in try recording.events(after: "session.resume") { try gateway.socket.deliver(frame) }
        // Its words reach this app only as the stored prompt, once the turn is over.
        let history = try await gateway.answer(
            1, method: "session.history", result: recording.result(of: "session.history"))
        #expect(history["profile"] == "scout")
        try await waitUntilOnMain { thread.state.items.count == before + 2 }

        guard case .result(let title, let output) = thread.state.items[before].content else {
            Issue.record("Expected the routine's result, got \(thread.state.items[before].content)")
            return
        }
        #expect(title == "From the routine “probe routine”")
        #expect(output.hasSuffix("routine says hi"))
        guard case .assistant(let reply) = thread.state.items[before + 1].content else {
            Issue.record("Expected the reply")
            return
        }
        #expect(reply.hasPrefix("ECHO: [Cronjob"))
        #expect(!thread.state.isRunning)
    }
}

/// The calls whose canonical form differs from the legacy one, with a scripted gateway.
@MainActor
struct CanonicalCallTests {
    private let snapshot: JSONValue = [
        "session_id": "local-1", "running": false, "execution_generation": 3, "revision": 5,
        "subscription_id": "sub-1", "replay_epoch": "e1", "last_sequence": 0, "display_messages": [],
    ]

    private func attach() async throws -> (JSONRPCChannel, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        gateway.socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"session_authority":true}}}"#
        )
        _ = try await channel.waitUntilReady()
        async let opened = BotChat.open(profile: "scout", knownID: "local-1", dialect: .canonical, on: channel)
        _ = try await gateway.answer(0, method: "session.resume", result: snapshot)
        _ = try await opened
        return (channel, gateway)
    }

    /// Opening a chat mid-reply reads the reply so far, and what it asked meanwhile.
    @Test func openingMidReplyKeepsWhatItAsked() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        gateway.socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"session_authority":true}}}"#
        )
        _ = try await channel.waitUntilReady()
        async let opening = BotChat.open(profile: "scout", knownID: "local-1", dialect: .canonical, on: channel)
        var running = snapshot
        if case .object(var fields) = running {
            fields["running"] = true
            fields["last_sequence"] = 2000
            fields["pending"] = [["admission_id": "a1", "status": "started", "input_id": "in-1", "text": "Clean up"]]
            running = .object(fields)
        }
        _ = try await gateway.answer(0, method: "session.resume", result: running)
        // The gateway keeps a session's last 512 frames, so earlier ones only make it say "truncated".
        let tooMuch = try await gateway.answer(
            1, method: "session.events.since", result: ["replay_epoch": "e1", "truncated": true, "events": []])
        #expect(tooMuch["last_sequence"] == 1489)
        let replay = try await gateway.answer(
            2, method: "session.events.since",
            result: [
                "replay_epoch": "e1", "truncated": false,
                "events": [
                    ["type": "message.delta", "admission_id": "a1", "payload": ["text": "On it. "]],
                    [
                        "type": "approval.request", "admission_id": "a1",
                        "payload": [
                            "kind": "approval", "prompt_id": "p1", "execution_generation": 3, "command": "rm -rf build",
                            "choices": ["once", "deny"],
                        ],
                    ],
                ],
            ])
        #expect(replay["replay_epoch"] == "e1")
        #expect(replay["last_sequence"] == 1873)
        let opened = try await opening
        #expect(opened.inflight?.assistant == "On it. ")
        #expect(opened.openRequests.compactMap(ApprovalPrompt.init).map(\.command) == ["rm -rf build"])
    }

    @Test func imagesRideWithTheNextMessage() async throws {
        let (channel, gateway) = try await attach()
        async let staged = channel.call(
            "image.attach_bytes", params: ["session_id": "local-1", "content_base64": "AA==", "filename": "a.png"])
        _ = try await gateway.answer(
            1, method: "image.attach_bytes",
            result: ["attached": true, "path": "/cache/images/a.png", "mime": "image/png"])
        _ = try await staged
        async let second = channel.call(
            "image.attach_bytes", params: ["session_id": "local-1", "content_base64": "AA==", "filename": "b.png"])
        _ = try await gateway.answer(
            2, method: "image.attach_bytes",
            result: ["attached": true, "path": "/cache/images/b.png", "mime": "image/png"])
        _ = try await second
        // Taking one back sends nothing: it just stays out of the message.
        _ = try await channel.call("image.detach", params: ["session_id": "local-1", "path": "/cache/images/b.png"])

        async let sent = channel.call("prompt.submit", params: ["session_id": "local-1", "text": "Look"])
        let submitted = try await gateway.answer(3, method: "prompt.submit", result: ["status": "queued"])
        _ = try await sent
        #expect(submitted["attachments"] == [["path": "/cache/images/a.png", "mime": "image/png"]])

        async let next = channel.call("prompt.submit", params: ["session_id": "local-1", "text": "Again"])
        #expect(try await gateway.answer(4, method: "prompt.submit", result: [:])["attachments"] == nil)
        _ = try await next
    }

    @Test func steeringAnEndedTurnSaysRejectedSoTheAppSendsIt() async throws {
        let (channel, gateway) = try await attach()
        async let steered = channel.call("session.steer", params: ["session_id": "local-1", "text": "Also cats"])
        let params = try await gateway.answer(
            1, method: "session.steer", error: (4001, "stale_generation"), data: ["reason": "stale_generation"])
        #expect(params["execution_generation"] == 3)
        #expect(try await steered == ["status": "rejected"])
    }

    /// Only `delivered: false` says no agent saw it. A plain "rejected" can follow delivery (a steer
    /// whose acknowledgement timed out), so sending it again could ask twice.
    @Test func aSteerTheAgentMayHaveTakenIsntSentAgain() async throws {
        let (channel, gateway) = try await attach()
        async let unsure = channel.call("session.steer", params: ["session_id": "local-1", "text": "Also cats"])
        _ = try await gateway.answer(
            1, method: "session.steer", result: ["status": "rejected", "text": "Also cats", "execution_generation": 3])
        #expect(try await unsure["status"] == "unconfirmed")

        async let unseen = channel.call("session.steer", params: ["session_id": "local-1", "text": "Also dogs"])
        _ = try await gateway.answer(
            2, method: "session.steer",
            result: ["status": "rejected", "text": "Also dogs", "execution_generation": 3, "delivered": false])
        #expect(try await unseen["status"] == "rejected")
    }

    @Test func undoRewindsToYourLastMessageOnTheNewestFences() async throws {
        let (channel, gateway) = try await attach()
        async let undone = channel.call("session.undo", params: ["session_id": "local-1"])
        _ = try await gateway.answer(
            1, method: "session.history",
            result: [
                "messages": [
                    ["role": "user", "content": "Plan my week", "row_id": 8], ["role": "assistant", "row_id": 9],
                    // A routine's result after it isn't yours to take back.
                    [
                        "role": "user", "text": "[Cronjob \"Brief\" output — scheduled job, not the user.]\n\nHi",
                        "display_kind": "internal_notification", "row_id": 10,
                    ],
                    ["role": "assistant", "row_id": 11],
                ]
            ])
        let first = try await gateway.answer(
            2, method: "session.mutate", error: (4001, "revision_conflict"),
            data: ["reason": "revision_conflict", "revision": 6, "execution_generation": 4])
        #expect(first["operation"] == "rewind")
        #expect(first["payload"] == ["target_message_id": 8])
        #expect(first["expected_revision"] == 5)
        #expect(first["expected_generation"] == 3)
        // Tried again once on the fences the refusal carried, as a new request.
        let second = try await gateway.answer(
            3, method: "session.mutate", result: ["revision": 7, "execution_generation": 5, "rewound_count": 2])
        #expect(second["expected_revision"] == 6)
        #expect(second["expected_generation"] == 4)
        #expect(second["request_id"] != first["request_id"])
        #expect(try await undone == ["removed": 2])
    }

    /// The gateway moves the generation when it takes a message, before the turn's first event, so
    /// Stop pressed straight after sending carries the old one.
    @Test func stopRightAfterSendingStopsTheNewTurn() async throws {
        let (channel, gateway) = try await attach()
        async let stopped = channel.call("session.interrupt", params: ["session_id": "local-1"])
        let first = try await gateway.answer(
            1, method: "session.interrupt", error: (4001, "stale_generation"),
            data: ["reason": "stale_generation", "execution_generation": 4])
        #expect(first["execution_generation"] == 3)
        let second = try await gateway.answer(2, method: "session.interrupt", result: ["running": true])
        #expect(second["execution_generation"] == 4)
        _ = try await stopped
    }

    @Test func closingDetachesThisAppOnly() async throws {
        let (channel, gateway) = try await attach()
        async let closed = channel.call("session.close", params: ["session_id": "local-1"])
        #expect(
            try await gateway.answer(1, method: "session.detach", result: ["detached": true])
                == ["session_id": "local-1", "subscription_id": "sub-1", "profile": "scout"])
        _ = try await closed
    }

    @Test func usageComesFromSessionInfo() async throws {
        let (channel, gateway) = try await attach()
        async let usage = channel.call("session.usage", params: ["session_id": "local-1"])
        _ = try await gateway.answer(1, method: "session.info", result: ["usage": ["input": 12, "context_max": 100]])
        #expect(try await usage == ["input": 12, "context_max": 100])
    }

    @Test func requestsTheAppDoesntShowAreLeftForOtherApps() async throws {
        let (channel, gateway) = try await attach()
        await channel.decline("srq-1", code: 4404, message: "Not shown here")
        await channel.respond(to: "srq-2", result: ["value": ""])
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1] == ["jsonrpc": "2.0", "id": "srq-2", "result": ["value": ""]])
    }
}
