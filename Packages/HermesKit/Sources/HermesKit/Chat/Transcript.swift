import Foundation

/// One thing shown in a chat, in order.
public struct TranscriptItem: Identifiable, Equatable, Sendable, Codable {
    public enum Content: Equatable, Sendable, Codable {
        case user(String)
        case assistant(String)
        /// Consecutive tool calls, shown as one collapsible line.
        case activity([ToolStep])
        /// A centred system line, e.g. "Stopped" or an error.
        case notice(String)
    }

    public let id: Int
    public var content: Content
}

/// One tool call the agent made.
public struct ToolStep: Identifiable, Equatable, Sendable, Codable {
    public enum State: Equatable, Sendable, Codable {
        case running, done, failed
    }

    public let id: String
    public var name: String
    /// A short argument preview from the gateway, e.g. a file path or command.
    public var context: String
    public var summary: String?
    public var duration: TimeInterval?
    public var state: State
}

/// A message from `session.resume`: the gateway's display projection of the stored history.
struct HistoryMessage: Decodable, Sendable, Equatable {
    let role: String
    let text: String?
    /// Tool rows only.
    let name: String?
    let context: String?
    let toolCallId: String?
    /// Unix seconds, when the gateway knows it.
    let timestamp: Double?

    init(
        role: String, text: String? = nil, name: String? = nil, context: String? = nil, toolCallId: String? = nil,
        timestamp: Double? = nil
    ) {
        self.role = role
        self.text = text
        self.name = name
        self.context = context
        self.toolCallId = toolCallId
        self.timestamp = timestamp
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        context = try? container.decodeIfPresent(String.self, forKey: .context)
        toolCallId = try? container.decodeIfPresent(String.self, forKey: .toolCallId)
        timestamp = try? container.decodeIfPresent(Double.self, forKey: .timestamp)
    }

    private enum CodingKeys: String, CodingKey { case role, text, name, context, toolCallId, timestamp }
}

/// A turn the gateway was still running when the app attached: what the user asked and the
/// reply streamed so far.
struct InflightTurn: Equatable, Sendable {
    let user: String
    let assistant: String
}

/// Everything a chat shows, built from history and then advanced by live gateway events.
public struct ThreadState: Equatable, Sendable, Codable {
    public private(set) var items: [TranscriptItem] = []
    /// The reply streaming in right now. It becomes an assistant item when the turn moves on or ends.
    public private(set) var draft = ""
    public private(set) var isRunning = false
    private var nextID = 0
    /// `items.count` when the current turn started, to tell whether the turn has replied yet.
    private var turnStart = 0

    public init() {}

    init(history: [HistoryMessage], running: Bool, inflight: InflightTurn? = nil) {
        for message in history {
            switch message.role {
            case "user":
                if let text = message.text?.nonBlank { append(.user(text)) }
            case "assistant":
                if let text = message.text?.nonBlank { append(.assistant(text)) }
            case "tool":
                let step = ToolStep(
                    id: message.toolCallId ?? "history-\(nextID)", name: message.name ?? "tool",
                    context: message.context ?? "", state: .done)
                addStep(step)
            default:
                break
            }
        }
        isRunning = running
        turnStart = items.count
        if running, let inflight {
            // The running turn's prompt may not be in the stored history yet.
            if let user = inflight.user.nonBlank, items.last?.content != .user(user) {
                append(.user(user))
                turnStart = items.count
            }
            draft = inflight.assistant
        }
    }

    /// Keeps only the last `limit` items, for the offline cache. A running turn is cut off.
    func trimmed(to limit: Int) -> ThreadState {
        var copy = self
        copy.items = Array(items.suffix(limit))
        copy.draft = ""
        copy.isRunning = false
        copy.turnStart = copy.items.count
        return copy
    }

    /// The gateway accepted a new turn without a local echo first (a steer that arrived too late).
    mutating func beginTurn() {
        isRunning = true
        turnStart = items.count
    }

    /// Shows a message sent while the agent works. The turn keeps running and reads it as guidance.
    mutating func steerLocally(_ text: String) {
        sealDraft()
        append(.user(text))
    }

    /// Shows the user's message right away, before the gateway confirms the turn.
    mutating func sendLocally(_ text: String) {
        sealDraft()
        append(.user(text))
        isRunning = true
        turnStart = items.count
    }

    mutating func addNotice(_ text: String) {
        sealDraft()
        append(.notice(text))
    }

    mutating func endTurnLocally() {
        sealDraft()
        finishSteps(as: .failed)
        isRunning = false
    }

    /// Applies one gateway event for this chat's session. Unknown events are ignored.
    mutating func apply(_ event: GatewayEvent) {
        let payload = event.payload
        switch event.type {
        case "message.start":
            if !isRunning { turnStart = items.count }
            isRunning = true
        case "message.delta":
            if let text = payload["text"]?.stringValue { draft += text }
        case "message.interim":
            sealDraft()
            if payload["already_streamed"]?.boolValue != true, let text = payload["text"]?.stringValue?.nonBlank {
                append(.assistant(text))
            }
        case "tool.start":
            sealDraft()
            addStep(
                ToolStep(
                    id: payload["tool_id"]?.stringValue ?? "tool-\(nextID)",
                    name: payload["name"]?.stringValue ?? "tool",
                    context: payload["context"]?.stringValue ?? "",
                    state: .running))
        case "tool.complete":
            completeStep(payload)
        case "message.complete":
            complete(payload)
        case "error":
            if let message = payload["message"]?.stringValue?.nonBlank { addNotice(message) }
        default:
            break
        }
    }

    // MARK: - Turn handling

    private mutating func complete(_ payload: JSONValue) {
        let status = payload["status"]?.stringValue ?? "complete"
        let text = payload["text"]?.stringValue?.nonBlank
        let failed = status == "error" || status == "failed"
        if failed {
            draft = ""
            append(.notice(text ?? String(localized: "The reply failed.")))
        } else if !draft.isEmpty {
            sealDraft()
        } else if let text, !turnHasReply {
            // Providers that don't stream send the whole reply here.
            append(.assistant(text))
        }
        switch status {
        case "interrupted":
            append(.notice(String(localized: "Stopped")))
        case "partial":
            append(.notice(String(localized: "The reply may be incomplete.")))
        default:
            break
        }
        finishSteps(as: status == "complete" ? .done : .failed)
        isRunning = false
        turnStart = items.count
    }

    private var turnHasReply: Bool {
        items[min(turnStart, items.count)...].contains {
            if case .assistant = $0.content { return true }
            return false
        }
    }

    private mutating func sealDraft() {
        if let text = draft.nonBlank { append(.assistant(text)) }
        draft = ""
    }

    private mutating func append(_ content: TranscriptItem.Content) {
        items.append(TranscriptItem(id: nextID, content: content))
        nextID += 1
    }

    // MARK: - Tool steps

    /// Consecutive tool calls join the activity item right before them.
    private mutating func addStep(_ step: ToolStep) {
        if case .activity(var steps) = items.last?.content {
            steps.append(step)
            items[items.count - 1].content = .activity(steps)
        } else {
            append(.activity([step]))
        }
    }

    private mutating func completeStep(_ payload: JSONValue) {
        guard let id = payload["tool_id"]?.stringValue else { return }
        for index in items.indices.reversed() {
            guard case .activity(var steps) = items[index].content,
                let stepIndex = steps.firstIndex(where: { $0.id == id })
            else { continue }
            let failed = payload["result"]?["error"].map { $0 != .null } ?? false
            steps[stepIndex].state = failed ? .failed : .done
            steps[stepIndex].summary = payload["summary"]?.stringValue?.nonBlank
            if case .number(let seconds) = payload["duration_s"] { steps[stepIndex].duration = seconds }
            items[index].content = .activity(steps)
            return
        }
    }

    /// When a turn ends, no step can still be running.
    private mutating func finishSteps(as state: ToolStep.State) {
        for index in items.indices {
            guard case .activity(var steps) = items[index].content, steps.contains(where: { $0.state == .running })
            else { continue }
            for step in steps.indices where steps[step].state == .running { steps[step].state = state }
            items[index].content = .activity(steps)
        }
    }
}

extension String {
    /// `nil` for empty or whitespace-only strings.
    var nonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
