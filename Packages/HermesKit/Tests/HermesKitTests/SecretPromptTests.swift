import Foundation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
struct SecretPromptTests {
    private let value = "correct-horse-battery-staple"

    /// Shaped like `tui_gateway/contracts/server_requests.py` and `agent_callbacks.py`'s `secret_cb`.
    private let secretRequest: JSONValue = [
        "id": "srq-1", "method": "secret",
        "params": [
            "session_id": "live-1", "env_var": "TENOR_API_KEY", "prompt": "Enter your Tenor API key",
            "metadata": ["skill_name": "gif-search"],
        ],
    ]
    private let sudoRequest: JSONValue = [
        "id": "srq-2", "method": "sudo", "params": ["session_id": "live-1", "command": "sudo apt update"],
    ]

    private func openThread(_ requests: [JSONValue]) async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume",
            result: ["session_id": "live-1", "running": true, "messages": [], "open_requests": .array(requests)])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    private func cancel(_ id: String, method: String, reason: String) -> GatewayEvent {
        GatewayEvent(
            type: "request.cancel", sessionID: "live-1", seq: nil,
            payload: ["id": .string(id), "method": .string(method), "reason": .string(reason)])
    }

    @Test func promptsReadTheGatewaysParams() throws {
        let secret = try #require(
            SecretPrompt(
                ServerRequest(
                    id: "srq-1", method: "secret",
                    params: ["session_id": "s", "env_var": "TENOR_API_KEY", "prompt": "Enter it"])))
        #expect(secret.kind == .secret(name: "TENOR_API_KEY", message: "Enter it"))
        let sudo = try #require(SecretPrompt(ServerRequest(id: "srq-2", method: "sudo", params: ["session_id": "s"])))
        #expect(sudo.kind == .sudo(command: ""))
        #expect(SecretPrompt(ServerRequest(id: "x", method: "secret", params: ["session_id": "s"])) == nil)
        #expect(SecretPrompt(ServerRequest(id: "x", method: "vault.code", params: ["session_id": "s"])) == nil)
    }

    @Test func reopenedRequestsComeBackWithTheChatAndGoOnReconnect() async throws {
        let (thread, _) = try await openThread([secretRequest, sudoRequest])
        #expect(thread.secrets.map(\.id) == ["srq-1", "srq-2"])
        #expect(thread.approvals.isEmpty && thread.questions.isEmpty)
        #expect(thread.activity == .needsYou)
        thread.detach()
        #expect(thread.secrets.isEmpty)
    }

    @Test func receivingTheSamePromptTwiceShowsItOnce() async throws {
        let (thread, _) = try await openThread([secretRequest])
        thread.receive(try #require(thread.secrets.first))
        #expect(thread.secrets.count == 1)
    }

    @Test func answerGoesToTheGatewayAndNowhereElse() async throws {
        let (thread, gateway) = try await openThread([secretRequest])
        thread.answer(try #require(thread.secrets.first), with: value)
        try await waitUntil { gateway.socket.sent.count == 2 }

        let reply = gateway.socket.sent[1]
        #expect(reply["id"] == "srq-1")
        #expect(reply["result"]?["value"]?.stringValue == value)
        #expect(reply["error"] == nil)
        #expect(thread.secrets.isEmpty)
        #expect(thread.activity == .working)

        // The notice names what was asked for; the value is in nothing that's shown or cached.
        #expect(thread.state.items.last?.content == .notice("You sent TENOR_API_KEY"))
        let cached = String(decoding: try JSONEncoder().encode(thread.cacheEntry), as: UTF8.self)
        #expect(!cached.contains(value))
        #expect(!String(describing: thread.state.items).contains(value))
    }

    @Test func spacesInAnAnswerAreKept() async throws {
        let (thread, gateway) = try await openThread([sudoRequest])
        thread.answer(try #require(thread.secrets.first), with: " pass word ")
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1]["result"]?["value"]?.stringValue == " pass word ")
        #expect(thread.state.items.last?.content == .notice("You sent the sudo password"))
    }

    @Test func emptyAnswerSendsNothing() async throws {
        let (thread, gateway) = try await openThread([secretRequest])
        thread.answer(try #require(thread.secrets.first), with: "")
        // sleep-ok: nothing should be sent, so there is no event to wait for
        try await Task.sleep(for: .milliseconds(30))
        #expect(gateway.socket.sent.count == 1)
        #expect(thread.secrets.count == 1)
    }

    @Test(arguments: [("srq-1", "You skipped TENOR_API_KEY"), ("srq-2", "You skipped the sudo password")])
    func skippingAnswersWithAnEmptyValue(id: String, notice: String) async throws {
        let (thread, gateway) = try await openThread([secretRequest, sudoRequest])
        thread.skip(try #require(thread.secrets.first { $0.id == id }))
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1] == ["jsonrpc": "2.0", "id": .string(id), "result": ["value": ""]])
        #expect(thread.secrets.map(\.id) == [id == "srq-1" ? "srq-2" : "srq-1"])
        #expect(thread.state.items.last?.content == .notice(notice))
    }

    @Test func withdrawnPromptsDisappear() async throws {
        let (thread, gateway) = try await openThread([secretRequest, sudoRequest])
        let before = thread.state.items.count
        thread.apply(cancel("srq-1", method: "secret", reason: "interrupted"))
        #expect(thread.secrets.map(\.id) == ["srq-2"])
        #expect(thread.state.items.count == before)

        thread.apply(cancel("srq-2", method: "sudo", reason: "timeout"))
        #expect(thread.secrets.isEmpty)
        #expect(
            thread.state.items.last?.content == .notice("Nobody answered in time, so the sudo password wasn't sent."))
        #expect(gateway.socket.sent.count == 1)
    }

    @Test func recordedFramesLeaveOutTheAnswer() {
        let answer: JSONValue = ["jsonrpc": "2.0", "id": "srq-1", "result": ["value": .string(value)]]
        #expect(FrameRecorder.redacted(answer)["result"]?["value"] == "")
        #expect(FrameRecorder.redacted(answer)["id"] == "srq-1")
        let choice: JSONValue = ["jsonrpc": "2.0", "id": "srq-2", "result": ["choice": "once"]]
        #expect(FrameRecorder.redacted(choice) == choice)
    }

    @Test func unencryptedOnlyMeansPlainHTTPOffTheDeviceOutsideTailscale() async throws {
        for address in [
            "http://192.168.1.20:9119", "http://10.0.0.5", "http://hermes.local:9119", "http://mac-mini",
            "http://[fd12::1]:9119",
        ] {
            #expect(try GatewayAddress(parsing: address).isUnencrypted, "\(address)")
        }
        for address in [
            "https://hermes.example.com", "https://192.168.1.20", "http://localhost:9119", "http://127.0.0.1:9119",
            "http://[::1]:9119", "http://100.101.102.103:9119", "http://[fd7a:115c:a1e0::1]:9119",
        ] {
            #expect(try !GatewayAddress(parsing: address).isUnencrypted, "\(address)")
        }

        let thread = ChatThread(contactID: "hermes", channel: { nil })
        #expect(!thread.isLinkUnencrypted)
        thread.gateway = { try? GatewayAddress(parsing: "http://192.168.1.20:9119") }
        #expect(thread.isLinkUnencrypted)
    }

    // MARK: - Reaching a chat

    /// A model online with one agent, Hermes, whose Bot Chat is the live session `live-1`.
    private func connect() async throws -> (AppModel, FakeSocket) {
        let store = MemoryTokenStore()
        try store.save(
            TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            for: testGateway)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let socket = FakeSocket()
        let model = AppModel(
            tokenStore: store, http: ScriptedHTTP { _ in (200, #"{"ticket":"t1"}"#) }, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in socket })
        await model.restore()
        socket.deliver(#"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{}}}"#)
        let responder = Task {
            var answered = 0
            while !Task.isCancelled {
                let sent = socket.sent
                for frame in sent[min(answered, sent.count)...] {
                    guard let id = frame["id"]?.intValue, let method = frame["method"]?.stringValue else { continue }
                    let result: String
                    switch method {
                    case "profiles.list":
                        result = #"{"profiles":[{"name":"hermes","canonical_session":{"id":"stored-1"}}]}"#
                    case "groups.list": result = #"{"rooms":[]}"#
                    case "session.resume": result = #"{"session_id":"live-1","running":true,"messages":[]}"#
                    default: result = "{}"
                    }
                    socket.deliver(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(result)}"#)
                }
                answered = sent.count
                // sleep-ok: the fake socket has no signal for a new frame
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { responder.cancel() }
        try await waitUntilOnMain { model.contacts.first.map { model.thread(for: $0).isAttached } ?? false }
        return (model, socket)
    }

    private func deliver(_ id: String, _ method: String, session: String, extra: String = "", to socket: FakeSocket) {
        socket.deliver(
            #"{"jsonrpc":"2.0","id":"\#(id)","method":"\#(method)","params":{"session_id":"\#(session)"\#(extra)}}"#)
    }

    private func reply(to id: String, on socket: FakeSocket) -> JSONValue? {
        socket.sent.first { $0["id"]?.stringValue == id }
    }

    @Test func requestsReachTheirChat() async throws {
        let (model, socket) = try await connect()
        defer { model.signOut() }
        let thread = model.thread(for: try #require(model.contacts.first))
        deliver("srq-1", "secret", session: "live-1", extra: #","env_var":"TENOR_API_KEY","prompt":"Key?""#, to: socket)
        deliver("srq-2", "sudo", session: "live-1", extra: #","command":"sudo ls""#, to: socket)
        try await waitUntilOnMain { thread.secrets.count == 2 }
        #expect(thread.secrets[1].kind == .sudo(command: "sudo ls"))
        #expect(model.sidebarContacts.first?.activity == .needsYou)
        #expect(reply(to: "srq-1", on: socket) == nil)
    }

    /// A 4404 here would be stored as the secret, or tried as the password: with no other app
    /// attached, `server_requests._decline` settles it with a JSON error as the value.
    @Test func withoutAChatTheyAreSkippedNotDeclined() async throws {
        let (model, socket) = try await connect()
        defer { model.signOut() }
        deliver("srq-1", "secret", session: "elsewhere", extra: #","env_var":"KEY","prompt":"Key?""#, to: socket)
        deliver("srq-2", "sudo", session: "elsewhere", to: socket)
        // The right chat, but missing what the contract requires.
        deliver("srq-3", "secret", session: "live-1", to: socket)
        try await waitUntil {
            ["srq-1", "srq-2", "srq-3"].allSatisfy { id in socket.sent.contains { $0["id"]?.stringValue == id } }
        }
        for id in ["srq-1", "srq-2", "srq-3"] {
            let frame = try #require(reply(to: id, on: socket))
            #expect(frame["result"]?["value"] == "")
            #expect(frame["error"] == nil)
        }
    }

    @Test(arguments: ["preview.read", "terminal.read", "window.read", "tour", "mcp.setup"])
    func otherMethodsAreStillDeclined(method: String) async throws {
        let (model, socket) = try await connect()
        defer { model.signOut() }
        deliver("srq-1", method, session: "live-1", to: socket)
        try await waitUntil { socket.sent.contains { $0["id"]?.stringValue == "srq-1" } }
        let frame = try #require(reply(to: "srq-1", on: socket))
        #expect(frame["error"]?["code"]?.intValue == 4404)
        #expect(frame["result"] == nil)
        #expect(model.thread(for: try #require(model.contacts.first)).secrets.isEmpty)
    }
}
