import Foundation

/// Opens a profile's one long-lived conversation, the hidden session titled exactly "Bot Chat",
/// on a gateway speaking the legacy (dashboard) protocol.
///
/// Mirrors the official app's rules: the chat is found by its exact title, a failed lookup is an
/// error rather than a reason to create one, and a chat is only created when the gateway says none
/// exists. Creating a second Bot Chat would split the agent's conversation in two.
enum BotChat {
    static let title = "Bot Chat"

    struct Opened: Sendable {
        /// The live session ID: what `prompt.submit` takes and gateway events carry.
        let sessionID: String
        let history: [HistoryMessage]
        let running: Bool
        /// The history was too long for the gateway to send, so only new messages show.
        let historyOmitted: Bool
        /// The turn still running when the app attached, if any.
        var inflight: InflightTurn? = nil
        /// Questions (approvals, clarify, masked prompts) the gateway asked earlier and still waits on.
        var openRequests: [ServerRequest] = []
        /// The session's model and reasoning level, as `session.info` reports them.
        var info: JSONValue? = nil
    }

    /// `knownID` is the stored Bot Chat ID from the roster, when the gateway reported one.
    static func open(profile: String, knownID: String?, on channel: JSONRPCChannel) async throws -> Opened {
        var target = knownID
        if target == nil { target = try await find(profile: profile, on: channel) }
        if let target { return try await resume(profile: profile, sessionID: target, on: channel) }
        return try await create(profile: profile, on: channel)
    }

    static func find(profile: String, on channel: JSONRPCChannel) async throws -> String? {
        let result = try await channel.call(
            "session.list", params: ["profile": .string(profile), "title": .string(title), "include_hidden": true])
        guard case .array(let rows) = result["sessions"], let row = rows.first else { return nil }
        return row["resolved_id"]?.stringValue ?? row["id"]?.stringValue
    }

    static func resume(profile: String, sessionID: String, on channel: JSONRPCChannel) async throws -> Opened {
        var params: JSONValue = ["profile": .string(profile), "session_id": .string(sessionID)]
        var omitted = false
        let result: JSONValue
        do {
            result = try await channel.call("session.resume", params: params)
        } catch GatewayError.rpc(code: 4130, _) {
            // The gateway refuses to send a transcript over its size limit; attach without it.
            params = ["profile": .string(profile), "session_id": .string(sessionID), "omit_messages": true]
            result = try await channel.call("session.resume", params: params)
            omitted = true
        }
        guard let live = result["session_id"]?.stringValue else { throw GatewayError.invalidResponse }
        let history = (try? result["messages"]?.decode([HistoryMessage].self)) ?? []
        var requests: [ServerRequest] = []
        if case .array(let open) = result["open_requests"] {
            requests = open.compactMap { entry in
                guard let id = entry["id"]?.stringValue, let method = entry["method"]?.stringValue else { return nil }
                return ServerRequest(id: id, method: method, params: entry["params"] ?? .null)
            }
        }
        let inflight = result["inflight"].flatMap { turn -> InflightTurn? in
            guard case .object = turn else { return nil }
            return InflightTurn(user: turn["user"]?.stringValue ?? "", assistant: turn["assistant"]?.stringValue ?? "")
        }
        return Opened(
            sessionID: live, history: history, running: result["running"]?.boolValue ?? false,
            historyOmitted: omitted || result["messages_omitted"]?.boolValue == true, inflight: inflight,
            openRequests: requests, info: result["info"])
    }

    static func create(profile: String, on channel: JSONRPCChannel) async throws -> Opened {
        let created = try await channel.call(
            "session.create",
            params: [
                "profile": .string(profile), "title": .string(title), "hidden": true, "follow_profile_config": true,
            ])
        guard let live = created["session_id"]?.stringValue else { throw GatewayError.invalidResponse }
        do {
            // Title it now so the row exists and the next lookup finds it.
            _ = try await channel.call("session.title", params: ["session_id": .string(live), "title": .string(title)])
        } catch GatewayError.rpc(code: 4022, _) {
            // Another client created the Bot Chat meanwhile: adopt that one.
            if let existing = try await find(profile: profile, on: channel) {
                return try await resume(profile: profile, sessionID: existing, on: channel)
            }
            throw GatewayError.invalidResponse
        }
        return Opened(sessionID: live, history: [], running: false, historyOmitted: false, info: created["info"])
    }
}
