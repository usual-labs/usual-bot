import Foundation
import Testing

@testable import HermesKit

/// A fake gateway on the far side of a `FakeSocket`: answers each request in turn.
struct ScriptedGateway {
    let socket = FakeSocket()

    /// Waits for request number `index` (0-based), checks its method, and replies.
    func answer(_ index: Int, method: String, result: JSONValue? = nil, error: (Int, String)? = nil)
        async throws -> JSONValue
    {
        try await waitUntil { socket.sent.count > index }
        let request = socket.sent[index]
        #expect(request["method"]?.stringValue == method)
        var reply: [String: JSONValue] = ["jsonrpc": "2.0", "id": request["id"] ?? .null]
        if let error {
            reply["error"] = ["code": .number(Double(error.0)), "message": .string(error.1)]
        } else {
            reply["result"] = result ?? [:]
        }
        socket.deliver(String(decoding: try JSONEncoder().encode(JSONValue.object(reply)), as: UTF8.self))
        return request["params"] ?? .null
    }
}

struct BotChatTests {
    private func channel(_ gateway: ScriptedGateway) async -> JSONRPCChannel {
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        return channel
    }

    private let resumed: JSONValue = [
        "session_id": "live-1", "running": false,
        "messages": .array([["role": "user", "text": "Hi"], ["role": "assistant", "text": "Hello"]]),
    ]

    @Test func knownChatIsResumedDirectly() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let opened = BotChat.open(profile: "shiv", knownID: "stored-9", on: channel)

        let params = try await gateway.answer(0, method: "session.resume", result: resumed)
        #expect(params == ["profile": "shiv", "session_id": "stored-9"])
        let result = try await opened
        #expect(result.sessionID == "live-1")
        #expect(result.history.map(\.text) == ["Hi", "Hello"])
        #expect(!result.historyOmitted)
    }

    @Test func unknownChatIsFoundByExactTitle() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let opened = BotChat.open(profile: "shiv", knownID: nil, on: channel)

        let lookup = try await gateway.answer(
            0, method: "session.list",
            result: ["sessions": .array([["id": "root", "resolved_id": "tip", "title": "Bot Chat"]])])
        #expect(lookup == ["profile": "shiv", "title": "Bot Chat", "include_hidden": true])
        let resume = try await gateway.answer(1, method: "session.resume", result: resumed)
        #expect(resume["session_id"] == "tip")
        #expect(try await opened.sessionID == "live-1")
    }

    @Test func failedLookupNeverCreatesASecondChat() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let opened = BotChat.open(profile: "shiv", knownID: nil, on: channel)

        _ = try await gateway.answer(0, method: "session.list", error: (5006, "database is locked"))
        do {
            _ = try await opened
            Issue.record("Expected the lookup error")
        } catch {
            #expect(error as? GatewayError == .rpc(code: 5006, message: "database is locked"))
        }
        // sleep-ok: nothing should be sent, so there is no event to wait for
        try await Task.sleep(for: .milliseconds(50))
        #expect(gateway.socket.sent.count == 1)
    }

    @Test func missingChatIsCreatedAndTitled() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let opened = BotChat.open(profile: "ops", knownID: nil, on: channel)

        _ = try await gateway.answer(0, method: "session.list", result: ["sessions": .array([])])
        let create = try await gateway.answer(
            1, method: "session.create", result: ["session_id": "live-2", "stored_session_id": "stored-2"])
        #expect(create == ["profile": "ops", "title": "Bot Chat", "hidden": true, "follow_profile_config": true])
        let title = try await gateway.answer(2, method: "session.title", result: ["title": "Bot Chat"])
        #expect(title == ["session_id": "live-2", "title": "Bot Chat"])

        let result = try await opened
        #expect(result.sessionID == "live-2")
        #expect(result.history.isEmpty)
    }

    @Test func titleClashAdoptsTheExistingChat() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let opened = BotChat.open(profile: "ops", knownID: nil, on: channel)

        _ = try await gateway.answer(0, method: "session.list", result: ["sessions": .array([])])
        _ = try await gateway.answer(1, method: "session.create", result: ["session_id": "live-2"])
        _ = try await gateway.answer(2, method: "session.title", error: (4022, "title already in use"))
        _ = try await gateway.answer(
            3, method: "session.list", result: ["sessions": .array([["id": "theirs", "title": "Bot Chat"]])])
        let resume = try await gateway.answer(4, method: "session.resume", result: resumed)
        #expect(resume["session_id"] == "theirs")
        #expect(try await opened.sessionID == "live-1")
    }

    @Test func oversizedHistoryAttachesWithoutIt() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let opened = BotChat.open(profile: "shiv", knownID: "big", on: channel)

        _ = try await gateway.answer(0, method: "session.resume", error: (4130, "too many messages"))
        let retry = try await gateway.answer(
            1, method: "session.resume", result: ["session_id": "live-3", "running": true, "messages": .array([])])
        #expect(retry["omit_messages"] == true)
        let result = try await opened
        #expect(result.historyOmitted)
        #expect(result.running)
    }
}
