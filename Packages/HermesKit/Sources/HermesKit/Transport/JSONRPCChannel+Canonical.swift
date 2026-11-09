import Foundation

/// A refusal from the canonical protocol: `data.reason` says why, and for a stale fence the
/// fresh fences come with it (taken in `handle`).
struct CanonicalRefusal: Error, Equatable {
    let code: Int
    let reason: String
    let message: String
    let detail: String?

    /// The refusal in words. Session refusals' message is only the reason; others, such as a
    /// connector's, keep the gateway's own message.
    var gatewayError: GatewayError {
        guard message == reason else { return .rpc(code: code, message: message) }
        return .rpc(code: code, message: Self.describe(reason, detail: detail))
    }

    static func describe(_ reason: String, detail: String?) -> String {
        switch reason {
        case "not_found": return String(localized: "Hermes can't find this chat any more. Open it again.")
        case "permission_denied": return String(localized: "Hermes didn't allow that. Reconnect and try again.")
        case "profile_mismatch": return String(localized: "This gateway doesn't run this Bot, so it can't open here.")
        case "runtime_draining": return String(localized: "Hermes is restarting. Try again in a moment.")
        case "session_busy": return String(localized: "The agent is busy with this chat. Try again when it's done.")
        case "queue_full": return String(localized: "Too many messages are waiting. Let the agent catch up first.")
        case "stale_generation": return String(localized: "That reply has already ended.")
        case "storage_unavailable": return String(localized: "Hermes couldn't reach its storage. Try again.")
        case "model_resolution_failed": return String(localized: "Hermes couldn't find that model.")
        case "launch_credentials_unavailable":
            return String(localized: "Hermes has no working sign-in for that model's provider.")
        case "runtime_coordination_required":
            return String(localized: "The gateway can't run rooms right now. Restart Hermes and try again.")
        case "unsupported_command": return detail ?? String(localized: "Hermes doesn't run that command here.")
        case "invalid_params":
            return detail.map { String(localized: "Hermes didn't accept the request: \($0)") }
                ?? String(localized: "Hermes didn't accept the request. Updating Usual Bot or Hermes may fix it.")
        default:
            return detail ?? String(localized: "Hermes refused: \(reason.replacingOccurrences(of: "_", with: " ")).")
        }
    }
}

/// The gateway's own listener speaks the canonical session protocol; the app speaks the legacy
/// one. Each legacy call becomes what the canonical gateway takes, and its result the legacy
/// shape. Calls with nothing to translate go as they are, with their session's `profile`.
extension JSONRPCChannel {
    func canonicalCall(_ method: String, params: JSONValue, timeout: Duration, sensitive: Bool) async throws
        -> JSONValue
    {
        do {
            return try await translate(method, params: params, timeout: timeout, sensitive: sensitive)
        } catch let refusal as CanonicalRefusal {
            throw refusal.gatewayError
        }
    }

    /// A reply's fences and attach details, taken before the frames that follow it are read.
    func absorb(_ result: JSONValue, of method: String, session: String?, profile: String?) {
        switch method {
        case "session.resume", "session.create": canonical.absorbSnapshot(result, profile: profile)
        default: if let session { canonical.absorbFences(result, session: session) }
        }
    }

    private func translate(_ method: String, params: JSONValue, timeout: Duration, sensitive: Bool) async throws
        -> JSONValue
    {
        let session = params["session_id"]?.stringValue
        switch (method, session) {
        case ("session.resume", _):
            var fields = Self.fields(params)
            fields["display_projection"] = true
            return try await snapshot(send(method, params: .object(fields), timeout: timeout), timeout: timeout)
        case ("session.create", _):
            return try await create(params, timeout: timeout)
        case ("session.close", let session?):
            return try await detach(session, timeout: timeout)
        case ("prompt.submit", let session?):
            return try await submit(params, session: session, timeout: timeout)
        case ("image.attach_bytes", let session?):
            let result = try await routedSend(method, params, timeout: timeout, sensitive: sensitive)
            if result["attached"]?.boolValue == true, let path = result["path"] {
                canonical.update(session) {
                    $0.stagedImages.append(["path": path, "mime": result["mime"] ?? "image/png"])
                }
            }
            return result
        case ("image.detach", let session?):
            // Uploads are only staged, so taking one back is leaving it out of the next message.
            canonical.update(session) { staged in staged.stagedImages.removeAll { $0["path"] == params["path"] } }
            return [:]
        case ("session.steer", let session?):
            return try await steer(params, session: session, timeout: timeout)
        case ("session.interrupt", let session?):
            return try await interrupt(params, session: session, timeout: timeout)
        case ("session.undo", let session?):
            return try await rewind(session, timeout: timeout)
        case ("session.usage", let session?):
            let info = try await routedSend("session.info", ["session_id": .string(session)], timeout: timeout)
            return info["usage"] ?? [:]
        case ("session.compress", let session?):
            var payload: [String: JSONValue] = [:]
            if let focus = params["focus"] { payload["focus"] = focus }
            return try await mutate(session, "compress", payload: .object(payload), timeout: timeout)
        case ("session.events.since", let session?):
            var fields = Self.fields(params)
            if fields["replay_epoch"] == nil, let epoch = canonical.session(session)?.replayEpoch {
                fields["replay_epoch"] = .string(epoch)
            }
            return try await routedSend(method, .object(fields), timeout: timeout)
        case ("config.set", let session?) where params["key"] == "model":
            return try await switchModel(params, session: session, timeout: timeout)
        default:
            return try await routedSend(method, params, timeout: timeout, sensitive: sensitive)
        }
    }

    private func routedSend(_ method: String, _ params: JSONValue, timeout: Duration, sensitive: Bool = false)
        async throws -> JSONValue
    {
        try await send(method, params: canonical.routed(method, params), timeout: timeout, sensitive: sensitive)
    }

    // MARK: - Attaching

    /// The legacy shape of an attach's snapshot. A turn running then has its reply so far only in
    /// the session's replay frames, so they're read for it.
    private func snapshot(_ result: JSONValue, timeout: Duration) async -> JSONValue {
        var reply: String?
        var result = result
        if result["running"]?.boolValue == true, let session = result["session_id"]?.stringValue,
            let admission = CanonicalProtocol.startedAdmission(in: result)?["admission_id"]?.stringValue,
            let epoch = result["replay_epoch"]?.stringValue,
            let frames = await replay(session, epoch: epoch, latest: result["last_sequence"]?.intValue ?? 0, timeout)
        {
            reply = CanonicalProtocol.replyText(in: frames["events"], admission: admission)
            // Asked while this was read, after the snapshot: until the chat attaches, nothing shows them.
            let asked = CanonicalProtocol.waitingPrompts(in: frames["events"])
            let known = Set(CanonicalProtocol.rows(result["prompts"]).compactMap { $0["prompt_id"]?.stringValue })
            if case .object(var fields) = result {
                fields["prompts"] = .array(
                    CanonicalProtocol.rows(result["prompts"])
                        + asked.filter { !known.contains($0["prompt_id"]?.stringValue ?? "") })
                result = .object(fields)
            }
        }
        return canonical.legacySnapshot(result, replySoFar: reply)
    }

    /// The session's recent frames. Hermes keeps a session's last 512, fewer when they're large, and
    /// asking for more than it kept gets none at all (`truncated`), so this asks for less.
    private func replay(_ session: String, epoch: String, latest: Int, _ timeout: Duration) async -> JSONValue? {
        for window in [511, 127] {
            let frames = try? await routedSend(
                "session.events.since",
                [
                    "session_id": .string(session), "replay_epoch": .string(epoch),
                    "last_sequence": .number(Double(max(0, latest - window))),
                ], timeout: timeout)
            if let frames, frames["truncated"]?.boolValue != true { return frames }
            if frames == nil || latest <= window { return nil }
        }
        return nil
    }

    /// Creating with a title finds the chat with that title first, so two apps opening at once
    /// can't make two. `tui`, as Hermes's own terminal: the push plugin listens to chats people
    /// type in, and a chat's source can't change once it's made.
    private func create(_ params: JSONValue, timeout: Duration) async throws -> JSONValue {
        var fields = Self.fields(params)
        fields["source"] = fields["source"] ?? "tui"
        fields["request_id"] = fields["request_id"] ?? .string(UUID().uuidString)
        let created = try await send("session.create", params: .object(fields), timeout: timeout)
        guard let session = created["session_id"]?.stringValue else { throw GatewayError.invalidResponse }
        // Its snapshot has stored rows; attaching again sends the rows a chat shows.
        var resume: [String: JSONValue] = ["session_id": .string(session), "display_projection": true]
        resume["profile"] = fields["profile"]
        return await snapshot(
            try await send("session.resume", params: .object(resume), timeout: timeout), timeout: timeout)
    }

    /// Stops this app watching the session. Others may still be, so the session itself stays.
    private func detach(_ session: String, timeout: Duration) async throws -> JSONValue {
        guard let subscription = canonical.session(session)?.subscriptionID else { return [:] }
        let params = canonical.routed(
            "session.detach", ["session_id": .string(session), "subscription_id": .string(subscription)])
        canonical.forget(session)
        return try await send("session.detach", params: params, timeout: timeout)
    }

    // MARK: - Turns

    private func submit(_ params: JSONValue, session: String, timeout: Duration) async throws -> JSONValue {
        var fields = Self.fields(params)
        // Lets the gateway tell a retry from a second message.
        fields["submission_id"] = fields["submission_id"] ?? .string(UUID().uuidString)
        let staged = canonical.session(session)?.stagedImages ?? []
        if !staged.isEmpty { fields["attachments"] = .array(staged) }
        let result = try await routedSend("prompt.submit", .object(fields), timeout: timeout)
        canonical.update(session) { $0.stagedImages = [] }
        return result
    }

    /// `rejected` tells the app the turn has ended, so it sends the text as the next message.
    private func steer(_ params: JSONValue, session: String, timeout: Duration) async throws -> JSONValue {
        guard let generation = canonical.session(session)?.generation else { return ["status": "rejected"] }
        var fields = Self.fields(params)
        fields["execution_generation"] = .number(Double(generation))
        do {
            let result = try await routedSend("session.steer", .object(fields), timeout: timeout)
            // Nothing running took it, so it can go as the next message.
            if result["delivered"]?.boolValue == false { return ["status": "rejected"] }
            // A plain "rejected" can follow delivery (`CanonicalCorrectionAck` in Hermes's contract).
            if result["status"] == "rejected" { return ["status": "unconfirmed"] }
            return result
        } catch let refusal as CanonicalRefusal
            where ["stale_generation", "execution_not_ready", "unsupported_control", "session_idle"].contains(
                refusal.reason)
        {
            return ["status": "rejected"]
        }
    }

    /// Stops the running turn. The gateway moves the generation when it takes a message, before the
    /// turn's first event, so a refusal for an old one is tried once more on the one it names.
    private func interrupt(_ params: JSONValue, session: String, timeout: Duration, retried: Bool = false)
        async throws -> JSONValue
    {
        guard let generation = canonical.session(session)?.generation else { return [:] }
        var fields = Self.fields(params)
        fields["execution_generation"] = .number(Double(generation))
        do {
            return try await routedSend("session.interrupt", .object(fields), timeout: timeout)
        } catch let refusal as CanonicalRefusal where refusal.reason == "stale_generation" && !retried {
            return try await interrupt(params, session: session, timeout: timeout, retried: true)
        }
    }

    // MARK: - Edits

    /// Takes back the last message you sent and everything after it.
    private func rewind(_ session: String, timeout: Duration) async throws -> JSONValue {
        let history = try await routedSend("session.history", ["session_id": .string(session)], timeout: timeout)
        guard let row = CanonicalProtocol.lastSent(in: history["messages"]) else { return ["removed": 0] }
        let receipt = try await mutate(
            session, "rewind", payload: ["target_message_id": .number(Double(row))], timeout: timeout)
        return ["removed": receipt["rewound_count"] ?? 0]
    }

    private func switchModel(_ params: JSONValue, session: String, timeout: Duration) async throws -> JSONValue {
        guard let value = params["value"]?.stringValue, let pick = CanonicalProtocol.modelPick(value) else {
            return try await routedSend("config.set", params, timeout: timeout)
        }
        var payload: [String: JSONValue] = ["model": .string(pick.model)]
        if let provider = pick.provider { payload["provider"] = .string(provider) }
        if params["confirm_expensive_model"]?.boolValue == true,
            let token = canonical.session(session)?.modelConfirmation
        {
            payload["confirm"] = .string(token)
        }
        let receipt = try await mutate(session, "model", payload: .object(payload), timeout: timeout)
        canonical.update(session) { $0.modelConfirmation = receipt["confirm"]?.stringValue }
        return CanonicalProtocol.legacyModelResult(receipt)
    }

    /// One `session.mutate`, fenced on the newest revision and turn. A stale fence is refused
    /// with the fresh ones, so it's tried once more on those.
    func mutate(_ session: String, _ operation: String, payload: JSONValue, timeout: Duration) async throws
        -> JSONValue
    {
        var attempt = 0
        while true {
            let fences = canonical.session(session)
            var fields: [String: JSONValue] = [
                "session_id": .string(session), "request_id": .string(UUID().uuidString),
                "operation": .string(operation), "payload": payload,
                "expected_revision": .number(Double(fences?.revision ?? 0)),
            ]
            // Renaming is the one edit a running turn doesn't fence.
            if operation != "rename" { fields["expected_generation"] = .number(Double(fences?.generation ?? 0)) }
            do {
                return try await routedSend("session.mutate", .object(fields), timeout: timeout)
            } catch let refusal as CanonicalRefusal
                where attempt == 0 && ["revision_conflict", "stale_generation"].contains(refusal.reason)
            {
                attempt += 1
            }
        }
    }

    static func fields(_ params: JSONValue) -> [String: JSONValue] {
        if case .object(let object) = params { return object }
        return [:]
    }
}

extension CanonicalProtocol {
    /// The row of your newest message, as `ChatThread.lastSent` sees it: not a routine's result or
    /// another of the turns Hermes starts itself.
    static func lastSent(in messages: JSONValue?) -> Int? {
        rows(messages).last { row in
            guard row["role"] == "user" else { return false }
            let text = (row["text"] ?? row["content"])?.stringValue ?? ""
            let content = GatewayTurn.content(
                text: text, kind: row["display_kind"]?.stringValue,
                title: row["display_metadata"]?["display_text"]?.stringValue)
            if case .user = content { return true }
            return false
        }?["row_id"]?.intValue
    }

    /// `config.set model`'s value, `<model> --provider <provider> --session`.
    static func modelPick(_ value: String) -> (model: String, provider: String?)? {
        var words = value.split(separator: " ").map(String.init).filter { $0 != "--session" }
        var provider: String?
        if let index = words.firstIndex(of: "--provider"), index + 1 < words.count {
            provider = words[index + 1]
            words.removeSubrange(index...(index + 1))
        }
        guard words.count == 1 else { return nil }
        return (words[0], provider)
    }

    /// A model switch's receipt as `config.set` answered: asking for a yes, held for the next
    /// turn, or done, with any warning.
    static func legacyModelResult(_ receipt: JSONValue) -> JSONValue {
        var result: [String: JSONValue] = [:]
        let status = receipt["status"]?.stringValue
        if status == "confirmation_required" || receipt["confirm_required"]?.boolValue == true {
            result["confirm_required"] = true
            result["confirm_message"] = receipt["confirm_message"] ?? .null
        }
        if status == "deferred" { result["deferred"] = true }
        let warnings =
            rows(receipt["warnings"]).compactMap(\.stringValue) + [receipt["warning"]?.stringValue].compactMap { $0 }
        if !warnings.isEmpty { result["warning"] = .string(warnings.joined(separator: " ")) }
        return .object(result)
    }
}
