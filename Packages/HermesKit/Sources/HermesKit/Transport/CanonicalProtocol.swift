import Foundation

/// What the gateway's canonical session protocol (the listener `hermes gateway` runs itself)
/// asks a client to remember, and the translation between it and the legacy shapes the rest of
/// the app speaks. `JSONRPCChannel` keeps one per socket. Nothing here touches the network.
///
/// The gateway fences every session: `revision` for edits, `execution_generation` for anything
/// aimed at a turn, and the `subscription_id` an attach returned. Both numbers move on every turn
/// and edit, so they're taken from every result, refusal and event. Approvals and questions come
/// as events here, not requests, and are handed on as the requests the app already answers.
struct CanonicalProtocol {
    struct Session: Equatable {
        /// Sent with every call about the session: the gateway routes a Bot's sessions by it.
        var profile: String?
        var generation: Int?
        var revision: Int?
        var subscriptionID: String?
        /// The session's own event numbering; `seq` starts again when it changes.
        var replayEpoch: String?
        var lastSeq = 0
        /// Images uploaded for the next message. Uploads only stage them here: they reach the
        /// agent as the message's attachments.
        var stagedImages: [JSONValue] = []
        /// What a model switch that asked for a yes came with, for the switch that says yes.
        var modelConfirmation: String?
    }

    /// An approval or question the gateway asked as an event, under the ID the app answers by.
    struct Prompt: Equatable {
        enum Kind: Equatable { case approval, clarify }
        let kind: Kind
        let sessionID: String
        let generation: Int
    }

    enum Inbound: Equatable {
        case event(GatewayEvent)
        case request(ServerRequest)
    }

    /// Methods that take `profile` next to `session_id`. Others refuse keys they don't know.
    static let profileRouted: Set<String> = [
        "session.resume", "session.info", "session.history", "session.events.since", "session.interrupt",
        "session.steer", "session.mutate", "session.detach", "prompt.submit", "prompt.btw", "prompt.background",
        "approval.respond", "clarify.respond", "message.react", "file.attach", "image.attach_bytes",
        "commands.catalog", "command.dispatch", "slash.exec", "model.options", "config.set", "reload.mcp",
        "connection.respond",
    ]

    private(set) var sessions: [String: Session] = [:]
    private(set) var prompts: [String: Prompt] = [:]

    func session(_ id: String) -> Session? { sessions[id] }

    mutating func update(_ id: String, _ change: (inout Session) -> Void) {
        var session = sessions[id] ?? Session()
        change(&session)
        sessions[id] = session
    }

    mutating func forget(_ id: String) {
        sessions[id] = nil
        prompts = prompts.filter { $0.value.sessionID != id }
    }

    /// `params` with the profile its session lives in, when the call names a session but no profile.
    func routed(_ method: String, _ params: JSONValue) -> JSONValue {
        guard Self.profileRouted.contains(method), case .object(var object) = params, object["profile"] == nil,
            let id = (params["session_id"] ?? params["owner"]?["session_id"])?.stringValue,
            let profile = sessions[id]?.profile
        else { return params }
        object["profile"] = .string(profile)
        return .object(object)
    }

    // MARK: - Fences

    /// Takes the newest fences from anything about a session: a receipt, a refusal's data,
    /// `session.info` or `session.updated`. They only move forward; a replayed receipt can be older.
    mutating func absorbFences(_ value: JSONValue, session id: String) {
        update(id) { session in
            if let generation = value["execution_generation"]?.intValue {
                session.generation = max(session.generation ?? generation, generation)
            }
            if let revision = value["revision"]?.intValue {
                session.revision = max(session.revision ?? revision, revision)
            }
        }
    }

    /// An attach's snapshot (`session.resume`, `session.create`): fences, subscription and numbering.
    mutating func absorbSnapshot(_ result: JSONValue, profile: String?) {
        guard let id = result["session_id"]?.stringValue else { return }
        absorbFences(result, session: id)
        update(id) { session in
            if let profile { session.profile = profile }
            if let subscription = result["subscription_id"]?.stringValue { session.subscriptionID = subscription }
            if let epoch = result["replay_epoch"]?.stringValue, epoch != session.replayEpoch {
                session.replayEpoch = epoch
                session.lastSeq = 0
            }
            session.lastSeq = max(session.lastSeq, result["last_sequence"]?.intValue ?? 0)
        }
    }

    // MARK: - Attaching

    /// An attach's snapshot in the legacy shape: display rows as `messages`, the approvals and
    /// questions waiting as `open_requests`, and a running turn as `inflight`.
    mutating func legacySnapshot(_ result: JSONValue, replySoFar: String?) -> JSONValue {
        guard case .object(var object) = result, let id = result["session_id"]?.stringValue else { return result }
        if let display = result["display_messages"] { object["messages"] = display }
        var open: [JSONValue] = []
        if case .array(let requests) = result["open_requests"] { open = requests }
        if case .array(let waiting) = result["prompts"] {
            for prompt in waiting {
                guard let request = request(for: prompt, session: id) else { continue }
                open.append(["id": .string(request.id), "method": .string(request.method), "params": request.params])
            }
        }
        object["open_requests"] = .array(open)
        if result["running"]?.boolValue == true {
            let started = Self.startedAdmission(in: result)
            // The running prompt is usually stored already; then only the reply so far is new.
            let input = started?["input_id"]?.stringValue
            let stored = Self.rows(result["display_messages"]).contains {
                input != nil && $0["display_metadata"]?["submission_id"]?.stringValue == input
            }
            object["inflight"] = [
                "user": .string(stored ? "" : started?["text"]?.stringValue ?? ""),
                "assistant": .string(replySoFar ?? ""),
            ]
        }
        return .object(object)
    }

    /// The admission the running turn is working on.
    static func startedAdmission(in snapshot: JSONValue) -> JSONValue? {
        rows(snapshot["pending"]).first { $0["status"]?.stringValue == "started" }
    }

    /// The text a turn has streamed so far, from the session's replay frames.
    static func replyText(in frames: JSONValue?, admission: String) -> String {
        rows(frames).filter { $0["type"] == "message.delta" && $0["admission_id"]?.stringValue == admission }
            .compactMap { $0["payload"]?["text"]?.stringValue }.joined()
    }

    /// The approvals and questions asked in replay `frames` and not settled since.
    static func waitingPrompts(in frames: JSONValue?) -> [JSONValue] {
        var waiting: [JSONValue] = []
        for frame in rows(frames) {
            guard let type = frame["type"]?.stringValue, let id = frame["payload"]?["prompt_id"] else { continue }
            if type == "approval.request" || type == "clarify.request", let payload = frame["payload"] {
                waiting.append(payload)
            } else if type == "approval.settled" || type == "clarify.settled" {
                waiting.removeAll { $0["prompt_id"] == id }
            }
        }
        return waiting
    }

    // MARK: - Events

    /// One event frame's `params`, as what the app should see: nothing for a frame already seen
    /// or one that means nothing to it, a request for an approval or question.
    mutating func inbound(_ params: JSONValue) -> [Inbound] {
        guard let type = params["type"]?.stringValue else { return [] }
        let sessionID = params["session_id"]?.stringValue?.nonBlank
        var payload = params["payload"] ?? .null
        if let sessionID {
            if let generation = params["execution_generation"]?.intValue {
                absorbFences(["execution_generation": .number(Double(generation))], session: sessionID)
            }
            if let seq = params["seq"]?.intValue, let epoch = params["replay_epoch"]?.stringValue {
                var seen = false
                update(sessionID) { session in
                    if session.replayEpoch != epoch {
                        session.replayEpoch = epoch
                        session.lastSeq = 0
                    }
                    seen = seq <= session.lastSeq
                    session.lastSeq = max(session.lastSeq, seq)
                }
                // Attaching again replays frames the snapshot already has.
                if seen { return [] }
            }
        }
        func event(_ type: String, _ payload: JSONValue) -> [Inbound] {
            [.event(GatewayEvent(type: type, sessionID: sessionID, seq: params["seq"]?.intValue, payload: payload))]
        }
        switch type {
        case "session.info", "session.updated":
            if let sessionID { absorbFences(payload, session: sessionID) }
        case "approval.request", "clarify.request":
            guard let sessionID, let request = request(for: payload, session: sessionID) else { return [] }
            return [.request(request)]
        case "approval.settled", "clarify.settled":
            // Answered here or elsewhere, timed out, or the turn ended: the gateway doesn't say which.
            guard let id = payload["prompt_id"]?.stringValue else { return [] }
            prompts[id] = nil
            return event("request.cancel", ["id": .string(id), "reason": "resolved"])
        case "message.delta" where payload["text"] == .null:
            // Where one stretch of streamed text ends, as `already_streamed` said in the legacy protocol.
            return event("message.interim", ["already_streamed": true])
        case "message.complete" where payload["status"] == nil && payload["outcome"] == "cancelled":
            // A queued message taken back: no turn ran, so none ends.
            return []
        case "tool.complete":
            payload = Self.legacyToolResult(payload)
        default:
            break
        }
        return event(type, payload)
    }

    /// `tool.complete` sends its result as JSON text and says failure with `is_error`.
    static func legacyToolResult(_ payload: JSONValue) -> JSONValue {
        guard case .object(var object) = payload else { return payload }
        var result = payload["result"] ?? .null
        if let text = result.stringValue {
            result = (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .string(text)
        }
        if payload["is_error"]?.boolValue == true, result["error"] == nil || result["error"] == .null {
            let reason = result.stringValue ?? payload["result"]?.stringValue ?? "failed"
            if case .object(var fields) = result {
                fields["error"] = .string(reason)
                result = .object(fields)
            } else {
                result = ["error": .string(reason)]
            }
        }
        object["result"] = result
        return .object(object)
    }

    // MARK: - Approvals and questions

    /// An `approval.request` or `clarify.request` payload as the request the app answers.
    private mutating func request(for prompt: JSONValue, session id: String) -> ServerRequest? {
        guard let promptID = prompt["prompt_id"]?.stringValue, let generation = prompt["execution_generation"]?.intValue
        else { return nil }
        switch prompt["kind"]?.stringValue {
        case "approval":
            prompts[promptID] = Prompt(kind: .approval, sessionID: id, generation: generation)
            return ServerRequest(
                id: promptID, method: "approval",
                params: [
                    "session_id": .string(id), "command": prompt["command"] ?? "",
                    "description": prompt["description"] ?? "", "choices": prompt["choices"] ?? [],
                ])
        case "clarify":
            prompts[promptID] = Prompt(kind: .clarify, sessionID: id, generation: generation)
            let question: JSONValue = [
                "qid": .string(promptID), "question": prompt["question"] ?? "", "choices": prompt["choices"] ?? [],
                "multi_select": prompt["multi_select"] ?? false,
            ]
            return ServerRequest(
                id: promptID, method: "clarify", params: ["session_id": .string(id), "questions": [question]])
        default:
            return nil
        }
    }

    /// The call that answers an approval or question asked as an event, or `nil` for a request
    /// the gateway sent as one (answered with a plain response).
    mutating func answer(_ id: String, result: JSONValue) -> (method: String, params: JSONValue)? {
        guard let prompt = prompts.removeValue(forKey: id) else { return nil }
        var params: [String: JSONValue] = [
            "session_id": .string(prompt.sessionID), "execution_generation": .number(Double(prompt.generation)),
            "prompt_id": .string(id),
        ]
        switch prompt.kind {
        case .approval:
            params["choice"] = result["choice"] ?? "deny"
            return ("approval.respond", .object(params))
        case .clarify:
            // An empty answer is a skip.
            params["answer"] = .string(result["answers"]?[id]?.stringValue ?? "")
            return ("clarify.respond", .object(params))
        }
    }

    // MARK: - Helpers

    static func rows(_ value: JSONValue?) -> [JSONValue] {
        if case .array(let rows) = value { return rows }
        return []
    }
}
