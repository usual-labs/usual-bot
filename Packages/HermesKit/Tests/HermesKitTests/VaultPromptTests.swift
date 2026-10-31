import Foundation
import Testing

@testable import HermesKit

private func request(_ id: String, _ method: String, _ params: JSONValue) -> JSONValue {
    ["jsonrpc": "2.0", "id": .string(id), "method": .string(method), "params": params]
}

private let unlockRequest = request(
    "srq-u", "vault.unlock_prompt", ["session_id": "live-1", "backend": "bitwarden", "display_name": "Bitwarden"])
private let saveRequest = request(
    "srq-s", "vault.save_login", ["session_id": "live-1", "origin": "https://example.com", "site": "example.com"])
private let codeRequest = request("srq-c", "vault.code", ["session_id": "live-1", "site": "example.com", "hint": ""])

struct VaultPromptTests {
    private func prompt(_ method: String, _ params: JSONValue) -> VaultPrompt? {
        VaultPrompt(ServerRequest(id: "srq", method: method, params: params))
    }

    @Test func readsTheThreeRequests() {
        #expect(
            prompt("vault.unlock_prompt", ["session_id": "s", "backend": "op", "display_name": "1Password"])?.kind
                == .unlock(backend: "op", displayName: "1Password"))
        #expect(
            prompt("vault.unlock_prompt", ["session_id": "s", "backend": "op"])?.kind
                == .unlock(backend: "op", displayName: "op"))
        #expect(
            prompt("vault.save_login", ["session_id": "s", "origin": "https://a.example", "site": ""])?.kind
                == .saveLogin(origin: "https://a.example", site: "https://a.example"))
        #expect(
            prompt("vault.code", ["session_id": "s", "site": "a.example", "hint": .null])?.kind
                == .code(site: "a.example", hint: nil))
        #expect(prompt("vault.code", ["session_id": "s"])?.kind == .code(site: nil, hint: nil))
    }

    @Test func leavesEverythingElseAlone() {
        #expect(prompt("vault.unlock_prompt", ["session_id": "s"]) == nil)
        #expect(prompt("vault.save_login", ["session_id": "s", "origin": ""]) == nil)
        #expect(prompt("vault.code", ["site": "no session"]) == nil)
        #expect(prompt("sudo", ["session_id": "s"]) == nil)
        #expect(prompt("secret", ["session_id": "s", "env_var": "X"]) == nil)
    }

    @Test func loginsGoAsJSONAndNothingEmptyCountsAsAnAnswer() throws {
        let save = VaultPrompt(id: "1", sessionID: "s", kind: .saveLogin(origin: "https://a", site: "a"))
        let json = try #require(save.value(secret: " pass word ", identifier: " me@a "))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(value == ["identifier": "me@a", "password": " pass word "])
        #expect(save.value(secret: "", identifier: "me") == nil)
        #expect(save.value(secret: "p", identifier: "  ") == nil)

        let code = VaultPrompt(id: "2", sessionID: "s", kind: .code(site: nil, hint: nil))
        #expect(code.value(secret: " 123 456\n", identifier: nil) == "123 456")
        #expect(code.value(secret: "  ", identifier: nil) == nil)
    }
}

@MainActor
struct VaultChatTests {
    private func openThread(_ openRequests: [JSONValue] = [], unencrypted: Bool = false) async throws
        -> (ChatThread, ScriptedGateway)
    {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "scout", channel: { channel })
        thread.gatewayIsUnencrypted = { unencrypted }
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume",
            result: [
                "session_id": "live-1", "running": true, "messages": .array([]), "open_requests": .array(openRequests),
            ])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    private func cancel(_ id: String, reason: String) -> GatewayEvent {
        GatewayEvent(
            type: "request.cancel", sessionID: "live-1", seq: nil,
            payload: ["id": .string(id), "method": "vault.code", "reason": .string(reason)])
    }

    /// Everything the chat keeps: its transcript as the offline cache would store it.
    private func keptText(_ thread: ChatThread) throws -> String {
        String(decoding: try JSONEncoder().encode(thread.cacheEntry), as: UTF8.self)
    }

    @Test func promptsStillWaitingArriveWithTheChatAndWaitForYou() async throws {
        let (thread, _) = try await openThread([unlockRequest, saveRequest, codeRequest])
        #expect(thread.vaultPrompts.map(\.id) == ["srq-u", "srq-s", "srq-c"])
        #expect(thread.activity == .needsYou)
    }

    @Test func anUnlockAnswerGoesOutAndStaysOutOfTheChat() async throws {
        let (thread, gateway) = try await openThread([unlockRequest])
        #expect(thread.answer(thread.vaultPrompts[0], secret: "master-test"))
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1] == ["jsonrpc": "2.0", "id": "srq-u", "result": ["value": "master-test"]])
        #expect(thread.vaultPrompts.isEmpty)
        #expect(thread.state.items.last?.content == .notice("You sent the master password for Bitwarden"))
        #expect(try !keptText(thread).contains("master-test"))
    }

    @Test func aLoginAnswerIsTheJSONTheGatewayReads() async throws {
        let (thread, gateway) = try await openThread([saveRequest])
        #expect(thread.answer(thread.vaultPrompts[0], secret: "hunter2-test", identifier: "me@example.com"))
        try await waitUntil { gateway.socket.sent.count == 2 }
        let frame = gateway.socket.sent[1]
        #expect(frame["id"] == "srq-s")
        let value = try #require(frame["result"]?["value"]?.stringValue)
        #expect(
            try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))
                == ["identifier": "me@example.com", "password": "hunter2-test"])
        #expect(try !keptText(thread).contains("hunter2-test"))
    }

    @Test func aCodeAnswerGoesOutTrimmed() async throws {
        let (thread, gateway) = try await openThread([codeRequest])
        #expect(thread.answer(thread.vaultPrompts[0], secret: " 123456 "))
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1]["result"] == ["value": "123456"])
        #expect(try !keptText(thread).contains("123456"))
    }

    @Test func anIncompleteAnswerKeepsThePromptAndSendsNothing() async throws {
        let (thread, gateway) = try await openThread([saveRequest])
        #expect(!thread.answer(thread.vaultPrompts[0], secret: "hunter2-test", identifier: " "))
        #expect(thread.vaultPrompts.count == 1)
        try await Task.sleep(for: .milliseconds(30))
        #expect(gateway.socket.sent.count == 1)
    }

    @Test func skippingAnswersWithAnEmptyValue() async throws {
        let (thread, gateway) = try await openThread([codeRequest])
        thread.skip(thread.vaultPrompts[0])
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1] == ["jsonrpc": "2.0", "id": "srq-c", "result": ["value": ""]])
        #expect(thread.vaultPrompts.isEmpty)
        #expect(thread.state.items.last?.content == .notice("You skipped the code"))
    }

    @Test func anUnencryptedAddressTakesYourSaySoForEachAnswer() async throws {
        let (thread, gateway) = try await openThread([codeRequest], unencrypted: true)
        let prompt = try #require(thread.vaultPrompts.first)
        #expect(thread.vaultAnswersAreUnencrypted)
        #expect(!thread.answer(prompt, secret: "123456"))
        #expect(thread.vaultPrompts.count == 1)
        try await Task.sleep(for: .milliseconds(30))
        #expect(gateway.socket.sent.count == 1)

        #expect(thread.answer(prompt, secret: "123456", allowingUnencrypted: true))
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1]["result"] == ["value": "123456"])
    }

    @Test func aWithdrawnPromptGoesAwayQuietlyUnlessItTimedOut() async throws {
        let (thread, gateway) = try await openThread([unlockRequest, codeRequest])
        thread.apply(cancel("srq-u", reason: "interrupted"))
        #expect(thread.vaultPrompts.map(\.id) == ["srq-c"])
        #expect(thread.state.items.isEmpty)

        thread.apply(cancel("srq-c", reason: "timeout"))
        #expect(thread.vaultPrompts.isEmpty)
        #expect(thread.state.items.last?.content == .notice("Nobody entered the code in time."))
        #expect(gateway.socket.sent.count == 1)  // Nothing to answer once it's withdrawn.
    }

    @Test func anUnreadablePromptStillWaitingIsSkippedWhenTheChatAttaches() async throws {
        let unreadable = request("srq-bad", "vault.unlock_prompt", ["session_id": "live-1"])
        let (thread, gateway) = try await openThread([unreadable, codeRequest])
        #expect(thread.vaultPrompts.map(\.id) == ["srq-c"])
        try await waitUntil { gateway.socket.sent.count == 2 }
        let answer = try #require(gateway.socket.sent.dropFirst().first)
        #expect(answer == ["jsonrpc": "2.0", "id": "srq-bad", "result": ["value": ""]])
    }

    @Test func goingOfflineDropsPrompts() async throws {
        let (thread, _) = try await openThread([codeRequest])
        thread.detach()
        #expect(thread.vaultPrompts.isEmpty)
    }
}

/// The app itself, signed in and attached to a chat, answering server requests through `handle`.
@MainActor
struct VaultRoutingTests {
    /// Answers what the app asks on its own, so a test can put requests to a live model.
    private func serve(_ socket: FakeSocket) -> Task<Void, Never> {
        socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"replay_epoch":"e"}}}"#)
        return Task.detached {
            var seen = 0
            while !Task.isCancelled {
                let sent = socket.sent
                for frame in sent[seen...] where frame["method"] != nil {
                    let result: JSONValue
                    switch frame["method"]?.stringValue {
                    case "profiles.list":
                        result = [
                            "profiles": [
                                ["name": "scout", "canonical_session": ["id": "stored-1"]]
                            ]
                        ]
                    case "groups.list": result = ["rooms": []]
                    case "session.resume":
                        result = ["session_id": "live-1", "running": true, "messages": []]
                    default: result = [:]
                    }
                    let reply: JSONValue = ["jsonrpc": "2.0", "id": frame["id"] ?? .null, "result": result]
                    socket.deliver(String(decoding: try! JSONEncoder().encode(reply), as: UTF8.self))
                }
                seen = sent.count
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    private func signedIn() async throws -> (AppModel, ChatThread, FakeSocket, Task<Void, Never>) {
        let store = MemoryTokenStore()
        try store.save(
            TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"), for: testGateway)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let socket = FakeSocket()
        let model = AppModel(
            tokenStore: store, http: ScriptedHTTP { _ in (200, #"{"ticket":"t1"}"#) }, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in socket })
        let server = serve(socket)
        await model.restore()
        try await waitUntilOnMain { model.contacts.contains { $0.id == "scout" } }
        let contact = try #require(model.contacts.first { $0.id == "scout" })
        let thread = model.thread(for: contact)
        model.openThread(for: contact)
        try await waitUntilOnMain { thread.isAttached }
        return (model, thread, socket, server)
    }

    private func deliver(_ frame: JSONValue, to socket: FakeSocket) {
        socket.deliver(String(decoding: try! JSONEncoder().encode(frame), as: UTF8.self))
    }

    @Test func vaultRequestsReachTheirChatAndOthersAreStillDeclined() async throws {
        let (model, thread, socket, server) = try await signedIn()
        defer {
            server.cancel()
            model.signOut()
        }
        for frame in [unlockRequest, saveRequest, codeRequest] { deliver(frame, to: socket) }
        try await waitUntilOnMain { thread.vaultPrompts.count == 3 }
        #expect(!thread.vaultAnswersAreUnencrypted)  // `testGateway` is on Tailscale.

        // Methods without a card keep the fallback.
        for method in ["preview.read", "terminal.read"] {
            let id = JSONValue.string("srq-\(method)")
            deliver(request("srq-\(method)", method, ["session_id": "live-1"]), to: socket)
            try await waitUntil { declined(id, in: socket) == 4404 }
        }
        #expect(thread.vaultPrompts.count == 3)
        // Prompts on their cards get no answer of any kind until you give one.
        let answered = socket.sent.filter { ["srq-u", "srq-s", "srq-c"].contains($0["id"]?.stringValue ?? "") }
        #expect(answered.isEmpty)
    }

    /// A 4404 from the only attached app settles the request with error text, which the gateway
    /// would use as a master password or type in as a code. These must always skip instead.
    @Test(arguments: ["vault.unlock_prompt", "vault.save_login", "vault.code"])
    func vaultRequestsWithNoCardAreSkippedAndNeverDeclined(method: String) async throws {
        let (model, thread, socket, server) = try await signedIn()
        defer {
            server.cancel()
            model.signOut()
        }
        let valid: JSONValue = [
            "session_id": "someone-else", "backend": "bitwarden", "origin": "https://example.com",
            "site": "example.com",
        ]
        let cases: [(String, JSONValue)] = [
            ("no-chat", valid),  // A session this app has no chat for.
            ("no-session", ["backend": "bitwarden", "origin": "https://example.com"]),
            ("bad-params", .string("not an object")),
        ]
        for (name, params) in cases {
            deliver(request(name, method, params), to: socket)
            let id = JSONValue.string(name)
            try await waitUntil { socket.sent.contains { $0["id"] == id } }
            #expect(
                socket.sent.last(where: { $0["id"] == id }) == ["jsonrpc": "2.0", "id": id, "result": ["value": ""]])
        }
        #expect(!socket.sent.contains { $0["error"] != nil })
        #expect(thread.vaultPrompts.isEmpty)
    }

    /// Unreadable for a chat that exists: only `vault.code` has no required field.
    @Test(arguments: ["vault.unlock_prompt", "vault.save_login"])
    func aVaultRequestItCantReadIsSkippedInItsChat(method: String) async throws {
        let (model, thread, socket, server) = try await signedIn()
        defer {
            server.cancel()
            model.signOut()
        }
        deliver(request("srq-bad", method, ["session_id": "live-1"]), to: socket)
        try await waitUntil { socket.sent.contains { $0["id"] == "srq-bad" } }
        #expect(socket.sent.last(where: { $0["id"] == "srq-bad" })?["result"] == ["value": ""])
        #expect(declined("srq-bad", in: socket) == nil)
        #expect(thread.vaultPrompts.isEmpty)
    }

    @Test func aRequestCancelReachesThePrompt() async throws {
        let (model, thread, socket, server) = try await signedIn()
        defer {
            server.cancel()
            model.signOut()
        }
        deliver(codeRequest, to: socket)
        try await waitUntilOnMain { thread.vaultPrompts.count == 1 }
        socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"request.cancel","session_id":"live-1","payload":{"id":"srq-c","method":"vault.code","reason":"interrupted"}}}"#
        )
        try await waitUntilOnMain { thread.vaultPrompts.isEmpty }
    }

    @Test func eachAgentHasItsOwnVaultUntilSignOut() async throws {
        let (model, _, _, server) = try await signedIn()
        defer { server.cancel() }
        let contact = try #require(model.contacts.first)
        let vault = model.vault(for: contact)
        #expect(vault.profile == "scout")
        #expect(!vault.isUnencrypted)  // `testGateway` is on Tailscale; unknown counts as unencrypted.
        #expect(model.vault(for: contact) === vault)
        model.signOut()
        #expect(model.vault(for: contact) !== vault)
    }
}

/// The code the app declined request `id` with, if it did.
private func declined(_ id: JSONValue, in socket: FakeSocket) -> Int? {
    socket.sent.first { $0["id"] == id && $0["error"] != nil }?["error"]?["code"]?.intValue
}
