import Foundation
import Testing

@testable import HermesKit

@MainActor
struct ChatThreadTests {
    private let approvalRequest: JSONValue = [
        "id": "srq-1", "method": "approval",
        "params": [
            "session_id": "live-1", "request_id": "r1", "command": "git push -u origin main",
            "description": "Push to a remote", "choices": ["once", "session", "always", "deny"],
        ],
    ]

    /// Opens a thread against a scripted gateway; `resume` is the `session.resume` result.
    private func openThread(resume: JSONValue, cached: CachedThread? = nil, visible: Bool = false)
        async throws -> (ChatThread, ScriptedGateway)
    {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", cached: cached, channel: { channel })
        thread.isVisible = visible
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(0, method: "session.resume", result: resume)
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    private func event(_ type: String, _ payload: JSONValue = [:]) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "live-1", seq: nil, payload: payload)
    }

    @Test func approvalsStillWaitingArriveWithTheChat() async throws {
        let (thread, gateway) = try await openThread(resume: [
            "session_id": "live-1", "running": true, "messages": .array([]),
            "open_requests": .array([approvalRequest]),
        ])
        let approval = try #require(thread.approvals.first)
        #expect(approval.command == "git push -u origin main")
        #expect(approval.choices == [.once, .session, .always, .deny])
        #expect(thread.activity == .needsYou)

        thread.answer(approval, with: .once)
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1] == ["jsonrpc": "2.0", "id": "srq-1", "result": ["choice": "once"]])
        #expect(thread.approvals.isEmpty)
        #expect(thread.state.items.last?.content == .notice("You allowed “git push -u origin main” once"))
        #expect(thread.activity == .working)
    }

    @Test func expiredApprovalIsWithdrawnWithANotice() async throws {
        let (thread, _) = try await openThread(resume: [
            "session_id": "live-1", "running": true, "messages": .array([]),
            "open_requests": .array([approvalRequest]),
        ])
        thread.apply(event("request.cancel", ["id": "srq-1", "method": "approval", "reason": "timeout"]))
        #expect(thread.approvals.isEmpty)
        #expect(
            thread.state.items.last?.content
                == .notice("Nobody answered in time, so “git push -u origin main” didn't run."))
    }

    @Test func messageWhileWorkingSteersTheTurn() async throws {
        let (thread, gateway) = try await openThread(resume: [
            "session_id": "live-1", "running": true, "messages": .array([]),
        ])
        thread.send("Use the staging branch instead")
        let params = try await gateway.answer(1, method: "session.steer", result: ["status": "queued"])
        #expect(params == ["session_id": "live-1", "text": "Use the staging branch instead"])
        #expect(thread.state.items.map(\.content) == [.user("Use the staging branch instead")])
        #expect(thread.state.isRunning)
    }

    @Test func steerThatMissesTheTurnBecomesTheNextMessage() async throws {
        let (thread, gateway) = try await openThread(resume: [
            "session_id": "live-1", "running": true, "messages": .array([]),
        ])
        thread.send("One more thing")
        _ = try await gateway.answer(1, method: "session.steer", result: ["status": "rejected"])
        let params = try await gateway.answer(2, method: "prompt.submit", result: ["status": "streaming"])
        #expect(params["text"] == "One more thing")
        #expect(thread.state.isRunning)
    }

    @Test func runningTurnResumesWithItsPartialReply() async throws {
        let (thread, _) = try await openThread(resume: [
            "session_id": "live-1", "running": true,
            "messages": .array([["role": "user", "text": "Earlier"], ["role": "assistant", "text": "Answer"]]),
            "inflight": ["user": "Now this", "assistant": "Working on i", "streaming": true],
        ])
        #expect(thread.state.items.map(\.content) == [.user("Earlier"), .assistant("Answer"), .user("Now this")])
        #expect(thread.state.draft == "Working on i")
        thread.apply(event("message.delta", ["text": "t."]))
        thread.apply(event("message.complete", ["status": "complete", "text": "Working on it."]))
        #expect(thread.state.items.last?.content == .assistant("Working on it."))
    }

    @Test func unreadCountsRepliesSinceYouLastLooked() async throws {
        let lastViewed = Date(timeIntervalSince1970: 1_000)
        let cached = CachedThread(state: ThreadState(), lastViewed: lastViewed, unreadCount: 0)
        let (thread, _) = try await openThread(
            resume: [
                "session_id": "live-1", "running": false,
                "messages": .array([
                    ["role": "assistant", "text": "Old", "timestamp": 900],
                    ["role": "user", "text": "Question", "timestamp": 1_100],
                    ["role": "assistant", "text": "New 1", "timestamp": 1_200],
                    ["role": "assistant", "text": "New 2", "timestamp": 1_300],
                ]),
            ], cached: cached)
        #expect(thread.unreadCount == 2)

        thread.apply(event("message.start"))
        thread.apply(event("message.complete", ["status": "complete", "text": "Live reply"]))
        #expect(thread.unreadCount == 3)

        thread.isVisible = true
        #expect(thread.unreadCount == 0)
        thread.apply(event("message.start"))
        thread.apply(event("message.complete", ["status": "complete", "text": "Seen reply"]))
        #expect(thread.unreadCount == 0)
    }

    @Test func firstSightOfAChatHasNothingUnread() async throws {
        let (thread, _) = try await openThread(resume: [
            "session_id": "live-1", "running": false,
            "messages": .array([["role": "assistant", "text": "Hi", "timestamp": 1_200]]),
        ])
        #expect(thread.unreadCount == 0)
    }

    /// Shaped like the clarify requests a real gateway sent (one question, two choices).
    private let clarifyRequest: JSONValue = [
        "id": "srq-2", "method": "clarify",
        "params": [
            "session_id": "live-1",
            "questions": [
                [
                    "qid": "q0", "question": "Delete the test folder now?", "choices": ["Yes", "No"],
                    "multi_select": false,
                ]
            ],
        ],
    ]

    @Test func questionsAreAnsweredFromTheChat() async throws {
        let (thread, gateway) = try await openThread(resume: [
            "session_id": "live-1", "running": true, "messages": [], "open_requests": [clarifyRequest],
        ])
        let prompt = try #require(thread.questions.first)
        #expect(prompt.questions.map(\.choices) == [["Yes", "No"]])
        #expect(thread.activity == .needsYou)

        thread.answer(prompt, with: ["q0": ["Yes"]])
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(
            gateway.socket.sent[1] == [
                "jsonrpc": "2.0", "id": "srq-2", "result": ["answers": ["q0": "Yes"], "outcome": "submitted"],
            ])
        #expect(thread.questions.isEmpty)
        #expect(thread.state.items.last?.content == .user("Yes"))
    }

    @Test func skippingAQuestionCancelsIt() async throws {
        let (thread, gateway) = try await openThread(resume: [
            "session_id": "live-1", "running": true, "messages": [], "open_requests": [clarifyRequest],
        ])
        thread.skip(try #require(thread.questions.first))
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1] == ["jsonrpc": "2.0", "id": "srq-2", "result": ["outcome": "cancelled"]])
    }

    @Test func multiSelectAnswersAreSentAsAList() throws {
        let request = ServerRequest(
            id: "srq-3", method: "clarify",
            params: [
                "session_id": "s",
                "questions": [["qid": "q0", "question": "Which?", "choices": ["A", "B", "C"], "multi_select": true]],
            ])
        let question = try #require(ClarifyPrompt(request)?.questions.first)
        #expect(question.allowsMultiple)
        #expect(ClarifyPrompt.encode(["A", "C"], for: question) == #"["A","C"]"#)
        #expect(ClarifyPrompt(ServerRequest(id: "x", method: "clarify", params: ["session_id": "s"])) == nil)
    }

    @Test func cachedChatShowsWhileOfflineButCannotSend() {
        var state = ThreadState()
        state.sendLocally("Cached question")
        let cached = CachedThread(state: state.trimmed(to: 60), lastViewed: nil, unreadCount: 1)
        let thread = ChatThread(contactID: "hermes", cached: cached, channel: { nil })
        #expect(thread.phase == .ready)
        #expect(thread.state.items.map(\.content) == [.user("Cached question")])
        #expect(!thread.state.isRunning)
        #expect(!thread.canSend)
        #expect(thread.unreadCount == 1)
    }
}

struct ServerRequestTests {
    @Test func channelSurfacesRequestsAndAnswersThemByID() async throws {
        let socket = FakeSocket()
        let channel = JSONRPCChannel(socket: socket)
        await channel.start()
        socket.deliver(#"{"jsonrpc":"2.0","id":"srq-9","method":"clarify","params":{"session_id":"s","questions":[]}}"#)
        var requests = channel.requests.makeAsyncIterator()
        let request = try #require(await requests.next())
        #expect(request.id == "srq-9")
        #expect(request.method == "clarify")
        #expect(request.sessionID == "s")

        await channel.decline("srq-9", code: -32601, message: "nope")
        await channel.respond(to: "srq-10", result: ["choice": "deny"])
        try await waitUntil { socket.sent.count == 2 }
        #expect(socket.sent[0] == ["jsonrpc": "2.0", "id": "srq-9", "error": ["code": -32601, "message": "nope"]])
        #expect(socket.sent[1] == ["jsonrpc": "2.0", "id": "srq-10", "result": ["choice": "deny"]])
    }

    @Test func approvalAlwaysOffersDeny() throws {
        let request = ServerRequest(
            id: "srq-1", method: "approval",
            params: ["session_id": "s", "command": "rm -rf build", "choices": ["once"]])
        let approval = try #require(ApprovalPrompt(request))
        #expect(approval.choices == [.once, .deny])
        #expect(ApprovalPrompt(ServerRequest(id: "x", method: "clarify", params: ["session_id": "s"])) == nil)
    }
}

struct OfflineCacheTests {
    @Test func roundTripsAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "usualbot-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = OfflineCache(directory: directory)
        var state = ThreadState()
        state.sendLocally("Hi")
        let snapshot = OfflineCache.Snapshot(
            contacts: [Contact(id: "hermes", name: "Hermes", tint: "#6E7BFF", chatID: "c1")],
            threads: [
                "hermes": CachedThread(
                    state: state.trimmed(to: 60), lastViewed: Date(timeIntervalSince1970: 5), unreadCount: 2)
            ])

        try cache.save(snapshot, for: testGateway)
        #expect(cache.load(for: testGateway) == snapshot)
        #expect(cache.load(for: try GatewayAddress(parsing: "10.0.0.1:9119")) == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1 && !files[0].contains("100.83"))

        cache.delete(for: testGateway)
        #expect(cache.load(for: testGateway) == nil)
    }
}
