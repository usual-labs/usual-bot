import Foundation

/// One thing shown in a chat, in order.
public struct TranscriptItem: Identifiable, Equatable, Sendable, Codable {
    public enum Content: Equatable, Sendable, Codable {
        case user(String)
        case assistant(String)
        /// A reply in a room from the member with this room member ID.
        case member(id: String, text: String)
        /// Consecutive tool calls, shown as one collapsible line.
        case activity([ToolStep])
        /// A centred system line, e.g. "Stopped" or an error.
        case notice(String)
        /// What a background task (`/bg`) came back with: the task you gave and the agent's answer.
        case background(task: String, result: String)
        /// What a Hermes command printed, laid out for a terminal (tables, aligned columns).
        case output(String)
        /// Work Hermes finished on its own, such as a background process: a title, and what it
        /// reported for anyone who wants to look.
        case result(title: String, detail: String)
    }

    public let id: Int
    public var content: Content
    /// The message's row in the gateway's store, which reactions address. Messages that arrived
    /// live have none until the chat reloads.
    public var rowID: Int?
    /// Emoji reactions, one per author at most.
    public var reactions: [Reaction] = []
    /// When it was said: the gateway's time for history, the time it arrived for the rest. `nil`
    /// when the gateway didn't say, and in caches written before dates were kept.
    public var date: Date?

    init(id: Int, content: Content, rowID: Int? = nil, reactions: [Reaction] = [], date: Date? = nil) {
        self.id = id
        self.content = content
        self.rowID = rowID
        self.reactions = reactions
        self.date = date
    }

    public init(from decoder: any Decoder) throws {
        // Caches written before reactions existed have neither field.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        content = try container.decode(Content.self, forKey: .content)
        rowID = try container.decodeIfPresent(Int.self, forKey: .rowID)
        reactions = try container.decodeIfPresent([Reaction].self, forKey: .reactions) ?? []
        date = try container.decodeIfPresent(Date.self, forKey: .date)
    }

    private enum CodingKeys: String, CodingKey { case id, content, rowID, reactions, date }
}

/// An emoji on a message. Hermes keeps one per author (you, or the agent) and shows them on every
/// app attached to the chat; the agent's model never sees yours.
public struct Reaction: Equatable, Sendable, Codable {
    public let emoji: String
    public let byAgent: Bool

    public init(emoji: String, byAgent: Bool) {
        self.emoji = emoji
        self.byAgent = byAgent
    }

    /// Reads the gateway's `{"emoji", "author"}` rows.
    static func list(_ value: JSONValue?) -> [Reaction] {
        guard case .array(let rows) = value else { return [] }
        return rows.compactMap { row in
            row["emoji"]?.stringValue.map { Reaction(emoji: $0, byAgent: row["author"]?.stringValue == "agent") }
        }
    }

    /// Your reactions after picking `emoji` (Tapback rules): the same one again removes it, a
    /// different one replaces it, `nil` clears it.
    static func toggling(_ emoji: String?, in reactions: [Reaction]) -> [Reaction] {
        let previous = reactions.first { !$0.byAgent }
        var next = reactions.filter(\.byAgent)
        if let emoji, previous?.emoji != emoji { next.append(Reaction(emoji: emoji, byAgent: false)) }
        return next
    }
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
    /// How far a long step has got, when the tool says.
    public var progress: String? = nil
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
    var date: Date? { timestamp.map(Date.init(timeIntervalSince1970:)) }
    /// The message's row in the store; reactions address it.
    let rowId: Int?
    let reactions: [Reaction]
    /// What kind of row this is, when it isn't an ordinary message.
    let displayKind: String?
    /// The short title Hermes gave a row of that kind.
    let displayText: String?

    init(
        role: String, text: String? = nil, name: String? = nil, context: String? = nil, toolCallId: String? = nil,
        timestamp: Double? = nil, rowId: Int? = nil, reactions: [Reaction] = [], displayKind: String? = nil,
        displayText: String? = nil
    ) {
        self.role = role
        self.text = text
        self.name = name
        self.context = context
        self.toolCallId = toolCallId
        self.timestamp = timestamp
        self.rowId = rowId
        self.reactions = reactions
        self.displayKind = displayKind
        self.displayText = displayText
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        context = try? container.decodeIfPresent(String.self, forKey: .context)
        toolCallId = try? container.decodeIfPresent(String.self, forKey: .toolCallId)
        timestamp = try? container.decodeIfPresent(Double.self, forKey: .timestamp)
        rowId = try? container.decodeIfPresent(Int.self, forKey: .rowId)
        let metadata = try? container.decodeIfPresent(JSONValue.self, forKey: .displayMetadata)
        reactions = Reaction.list(metadata?["reactions"])
        displayKind = try? container.decodeIfPresent(String.self, forKey: .displayKind)
        displayText = metadata?["display_text"]?.stringValue
    }

    private enum CodingKeys: String, CodingKey {
        case role, text, name, context, toolCallId, timestamp, rowId, displayKind, displayMetadata
    }
}

/// A turn the gateway was still running when the app attached: what the user asked and the
/// reply streamed so far.
struct InflightTurn: Equatable, Sendable {
    let user: String
    let assistant: String
    var displayKind: String? = nil
    var displayText: String? = nil
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
    /// What the running turn is doing between messages.
    public private(set) var live = LiveActivity()
    /// Notices Hermes can replace or take back, by its key.
    private var keyedNotices: [String: Int] = [:]

    private enum CodingKeys: String, CodingKey { case items, draft, isRunning, nextID, turnStart }

    public init() {}

    /// `kept`: background tasks' answers, which the gateway's history lacks, put back in time order.
    /// `todoState`: the to-do list Hermes kept for this chat; it means something only while the
    /// turn that made it runs.
    init(
        history: [HistoryMessage], running: Bool, inflight: InflightTurn? = nil, kept: [BackgroundResult] = [],
        todoState: JSONValue? = nil
    ) {
        var pending = kept.sorted { $0.date < $1.date }[...]
        for message in history {
            if let time = message.timestamp {
                while let next = pending.first, next.date.timeIntervalSince1970 <= time {
                    append(.background(task: next.task, result: next.result), date: next.date)
                    pending.removeFirst()
                }
            }
            switch message.role {
            case "user":
                if let text = message.text?.nonBlank {
                    append(
                        GatewayTurn.content(text: text, kind: message.displayKind, title: message.displayText),
                        rowID: message.rowId, reactions: message.reactions, date: message.date)
                }
            case "assistant":
                if let text = message.text?.nonBlank {
                    append(.assistant(text), rowID: message.rowId, reactions: message.reactions, date: message.date)
                }
            case "tool":
                let step = ToolStep(
                    id: message.toolCallId ?? "history-\(nextID)", name: message.name ?? "tool",
                    context: message.context ?? "", state: .done)
                addStep(step, date: message.date)
            default:
                break
            }
        }
        for next in pending { append(.background(task: next.task, result: next.result), date: next.date) }
        isRunning = running
        turnStart = items.count
        if running, let inflight {
            // The running turn's prompt may not be in the stored history yet.
            if let user = inflight.user.nonBlank {
                let prompt = GatewayTurn.content(text: user, kind: inflight.displayKind, title: inflight.displayText)
                if items.last?.content != prompt {
                    append(prompt)
                    turnStart = items.count
                }
            }
            draft = inflight.assistant
        }
        if running, let todoState { live.restoreTodos(todoState) }
    }

    /// Keeps only the last `limit` items, for the offline cache. A running turn is cut off.
    func trimmed(to limit: Int) -> ThreadState {
        var copy = self
        copy.items = Array(items.suffix(limit))
        copy.draft = ""
        copy.isRunning = false
        copy.turnStart = copy.items.count
        copy.live = LiveActivity()
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

    /// Puts a turn's message where the turn began, for one sent from another device.
    mutating func insertPrompt(_ message: HistoryMessage, at index: Int) {
        guard index <= items.count, let text = message.text?.nonBlank else { return }
        append(
            GatewayTurn.content(text: text, kind: message.displayKind, title: message.displayText),
            rowID: message.rowId, reactions: message.reactions, date: message.date ?? .now)
        items.insert(items.removeLast(), at: index)
        if index <= turnStart { turnStart += 1 }
    }

    /// Shows a command you ran that answers with output instead of a turn.
    mutating func showCommand(_ text: String) {
        sealDraft()
        append(.user(text))
    }

    /// Drops `itemID` and everything after it: what an undo removed, when the gateway's copy
    /// can't be fetched.
    mutating func rewind(from itemID: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items.removeSubrange(index...)
        draft = ""
        isRunning = false
        live.endTurn()
        turnStart = items.count
    }

    /// A background task's answer joins the conversation without touching a running turn.
    mutating func addBackgroundResult(task: String, result: String) {
        sealDraft()
        append(.background(task: task, result: result))
    }

    mutating func addOutput(_ text: String) {
        sealDraft()
        append(.output(text))
    }

    mutating func addNotice(_ text: String) {
        sealDraft()
        append(.notice(text))
    }

    mutating func endTurnLocally() {
        sealDraft()
        finishSteps(as: .failed)
        isRunning = false
        live.endTurn()
    }

    /// Applies one gateway event for this chat's session. Unknown events are ignored.
    mutating func apply(_ event: GatewayEvent) {
        let payload = event.payload
        switch event.type {
        case "message.start":
            // A turn Hermes started itself may say why, for a viewer that didn't submit it.
            if let kind = payload["display_kind"]?.stringValue,
                let title = payload["display_text"]?.stringValue?.nonBlank,
                let text = payload["text"]?.stringValue?.nonBlank
            {
                sealDraft()
                append(GatewayTurn.content(text: text, kind: kind, title: title))
            }
            if !isRunning { turnStart = items.count }
            isRunning = true
        case "message.delta":
            if let text = payload["text"]?.stringValue { draft += text }
            live.moveOn()
        case "message.interim":
            sealDraft()
            if payload["already_streamed"]?.boolValue != true, let text = payload["text"]?.stringValue?.nonBlank {
                append(.assistant(text))
            }
        case "tool.start":
            sealDraft()
            live.moveOn()
            addStep(
                ToolStep(
                    id: payload["tool_id"]?.stringValue ?? "tool-\(nextID)",
                    name: payload["name"]?.stringValue ?? "tool",
                    context: payload["context"]?.stringValue ?? "",
                    state: .running))
        case "tool.progress":
            updateStep(payload)
        case "tool.complete":
            completeStep(payload)
        case "message.complete":
            complete(payload)
        case "error":
            if let message = payload["message"]?.stringValue?.nonBlank { addNotice(message) }
        case "notification.show":
            show(payload)
        case "notification.clear":
            clearNotice(payload)
        default:
            if event.type == "status.update", LiveActivity.isFallback(payload),
                let text = payload["text"]?.stringValue?.nonBlank
            {
                append(.notice(text))
            }
            applyLive(event)
        }
    }

    /// Hermes can send a helper to the background and end the turn, so helpers are followed with
    /// no turn running; then one that finishes has nothing left to show. All else needs a turn.
    private mutating func applyLive(_ event: GatewayEvent) {
        if event.type.hasPrefix("subagent.") {
            live.apply(event)
            if !isRunning { live.dropFinishedHelpers() }
        } else if isRunning {
            live.apply(event)
        }
    }

    // MARK: - Notices from Hermes

    /// Hermes's own notices sit above a streaming reply, so they don't split it in two.
    private mutating func show(_ payload: JSONValue) {
        guard let text = payload["text"]?.stringValue?.nonBlank else { return }
        let key = payload["key"]?.stringValue
        if let key, let id = keyedNotices[key], let index = items.firstIndex(where: { $0.id == id }) {
            items[index].content = .notice(text)
            return
        }
        append(.notice(text))
        if let key { keyedNotices[key] = nextID - 1 }
    }

    private mutating func clearNotice(_ payload: JSONValue) {
        guard let key = payload["key"]?.stringValue, let id = keyedNotices.removeValue(forKey: key),
            let index = items.firstIndex(where: { $0.id == id })
        else { return }
        items.remove(at: index)
        if index < turnStart { turnStart -= 1 }
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
        live.endTurn(finished: status == "complete")
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

    /// Anything that isn't from history is happening now.
    private mutating func append(
        _ content: TranscriptItem.Content, rowID: Int? = nil, reactions: [Reaction] = [], date: Date? = .now
    ) {
        items.append(TranscriptItem(id: nextID, content: content, rowID: rowID, reactions: reactions, date: date))
        nextID += 1
    }

    /// Shows a message's reactions; `rowID` fills in the store row of a message that arrived live.
    mutating func setReactions(_ reactions: [Reaction], rowID: Int? = nil, on itemID: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].reactions = reactions
        if let rowID { items[index].rowID = rowID }
    }

    // MARK: - Tool steps

    /// Consecutive tool calls join the activity item right before them.
    private mutating func addStep(_ step: ToolStep, date: Date? = .now) {
        if case .activity(var steps) = items.last?.content {
            steps.append(step)
            items[items.count - 1].content = .activity(steps)
        } else {
            append(.activity([step]), date: date)
        }
    }

    private mutating func updateStep(_ payload: JSONValue) {
        var progress = payload["message"]?.stringValue?.nonBlank
        if progress == nil, case .number(let percent) = payload["percent"] { progress = "\(Int(percent))%" }
        withStep(payload) { $0.progress = progress }
    }

    private mutating func completeStep(_ payload: JSONValue) {
        withStep(payload) { step in
            let failed = payload["result"]?["error"].map { $0 != .null } ?? false
            step.state = failed ? .failed : .done
            step.summary = payload["summary"]?.stringValue?.nonBlank
            step.progress = nil
            if case .number(let seconds) = payload["duration_s"] { step.duration = seconds }
        }
    }

    private mutating func withStep(_ payload: JSONValue, _ change: (inout ToolStep) -> Void) {
        guard let id = payload["tool_id"]?.stringValue else { return }
        for index in items.indices.reversed() {
            guard case .activity(var steps) = items[index].content,
                let stepIndex = steps.firstIndex(where: { $0.id == id })
            else { continue }
            change(&steps[stepIndex])
            items[index].content = .activity(steps)
            return
        }
    }

    /// When a turn ends, no step can still be running.
    private mutating func finishSteps(as state: ToolStep.State) {
        for index in items.indices {
            guard case .activity(var steps) = items[index].content, steps.contains(where: { $0.state == .running })
            else { continue }
            for step in steps.indices where steps[step].state == .running {
                steps[step].state = state
                steps[step].progress = nil
            }
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
