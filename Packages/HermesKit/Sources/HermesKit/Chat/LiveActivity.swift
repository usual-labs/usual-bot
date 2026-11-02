import Foundation

/// What a chat's agent is doing between its messages. None of it is cached: it means nothing
/// afterwards, and a chat reopened mid-turn gets the to-do list back from Hermes.
public struct LiveActivity: Equatable, Sendable {
    /// One line of the agent's to-do list.
    public struct Todo: Identifiable, Equatable, Sendable {
        public enum Status: Sendable { case pending, active, done, cancelled }

        public let id: String
        public let text: String
        public let status: Status

        init?(_ row: JSONValue) {
            guard let text = row["content"]?.stringValue?.nonBlank else { return nil }
            id = row["id"]?.stringValue ?? text
            self.text = text
            switch row["status"]?.stringValue {
            case "completed": status = .done
            case "in_progress": status = .active
            case "cancelled": status = .cancelled
            default: status = .pending
            }
        }
    }

    /// A subagent the turn handed part of the work to.
    public struct Helper: Identifiable, Equatable, Sendable {
        public enum Status: Sendable { case running, done, failed }

        public let id: String
        public var goal: String
        public var status = Status.running
        /// The tool it used last, and on what.
        public var tool: String?
        public var detail: String?
    }

    public private(set) var todos: [Todo] = []
    public private(set) var helpers: [Helper] = []
    /// A provider wait in Hermes's words.
    private var wait: String?
    private var compressing = false
    private var reasoning = ""
    /// Newest to-do snapshot seen; it outlives the turn, as an older one could still arrive.
    private var todoRevision = 0

    /// What the turn is waiting on, when that's something other than the model thinking.
    public var status: String? {
        compressing ? String(localized: "Compressing the conversation…") : wait
    }

    /// The latest line of the agent's reasoning, when Hermes is set to share it.
    public var thought: String? {
        reasoning.split(whereSeparator: \.isNewline).last.flatMap { String($0).nonBlank }
    }

    /// The list once it's worth showing: cancelled items count for nothing.
    public var countedTodos: [Todo] { todos.filter { $0.status != .cancelled } }

    mutating func apply(_ event: GatewayEvent) {
        let payload = event.payload
        switch event.type {
        case "status.update":
            switch payload["kind"]?.stringValue {
            case "compacting", "compressing": compressing = true
            case "compacted", "ready": compressing = false
            default: break
            }
        case "thinking.delta":
            // Most of these are spinner frames; only explained waits say anything.
            wait = Self.waitText(payload["text"]?.stringValue ?? "")
        case "reasoning.delta":
            reasoning = String((reasoning + (payload["text"]?.stringValue ?? "")).suffix(600))
        case "todo.updated":
            restoreTodos(payload)
        case "subagent.spawn_requested", "subagent.start", "subagent.thinking", "subagent.tool", "subagent.progress",
            "subagent.complete":
            updateHelper(event.type, payload)
        default:
            break
        }
    }

    /// The turn moved on to its reply or a tool: whatever it was waiting on is over.
    mutating func moveOn() {
        wait = nil
        reasoning = ""
    }

    /// A helper Hermes sent to the background outlasts a turn that finished; one that was stopped
    /// or failed takes its helpers with it.
    mutating func endTurn(finished: Bool = false) {
        var next = LiveActivity()
        next.todoRevision = todoRevision
        if finished { next.helpers = helpers.filter { $0.status == .running } }
        self = next
    }

    mutating func dropFinishedHelpers() {
        helpers.removeAll { $0.status != .running }
    }

    /// Takes a full to-do snapshot (`{todos, revision}`), unless a newer one was already seen.
    mutating func restoreTodos(_ snapshot: JSONValue) {
        guard case .array(let rows) = snapshot["todos"] else { return }
        let revision = snapshot["revision"]?.intValue ?? todoRevision
        guard revision >= todoRevision else { return }
        todoRevision = revision
        todos = rows.compactMap(Todo.init)
    }

    private mutating func updateHelper(_ type: String, _ payload: JSONValue) {
        // Hermes may leave the ID out; then a helper is its place in the batch, as in its own app.
        let goal = payload["goal"]?.stringValue?.nonBlank
        let place = "\(payload["parent_id"]?.stringValue ?? "root"):\(payload["task_index"]?.intValue ?? 0)"
        let id = payload["subagent_id"]?.stringValue?.nonBlank ?? "\(place):\(goal ?? "")"
        var helper = helpers.first { $0.id == id } ?? Helper(id: id, goal: goal ?? String(localized: "Helper"))
        if let goal { helper.goal = goal }
        if let tool = payload["tool_name"]?.stringValue?.nonBlank {
            helper.tool = tool
            helper.detail = payload["tool_preview"]?.stringValue?.nonBlank
        }
        if type == "subagent.complete" {
            let status = payload["status"]?.stringValue
            helper.status = status == nil || status == "completed" ? .done : .failed
            helper.tool = nil
            helper.detail = nil
        }
        if let index = helpers.firstIndex(where: { $0.id == id }) {
            helpers[index] = helper
        } else {
            helpers.append(helper)
        }
    }

    /// Hermes's explained waits and reconnects, without their leading symbol.
    static func waitText(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wait =
            #"^[⏳⚠↻⚙]\S*\s*((still\s+)?waiting on|loading|processing prompt|no (output|response)|model returned|rate limited|provider (overloaded|temporarily unavailable))"#
        guard value.range(of: wait, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return String(value.drop { !$0.isLetter })
    }

    /// Whether a status line says the chat left its model for a fallback.
    static func isFallback(_ payload: JSONValue) -> Bool {
        if payload["kind"]?.stringValue == "fallback" { return true }
        let pattern = "model fallback|provider fallback|switched to fallback|switching to fallback"
        return payload["text"]?.stringValue?.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
