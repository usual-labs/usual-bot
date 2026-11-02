import Foundation

/// One time a routine ran, from `/api/cron/jobs/{id}/runs`.
///
/// An agent run is a stored session whose messages can be read. A script-only run left an output
/// file, and the gateway sends only a short preview of it.
public struct RoutineRun: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case finished
        /// Stopped without a final reply from the agent.
        case incomplete
        case failed
    }

    public let id: String
    public let started: Date
    public let status: Status
    /// The first part of what it said, when the gateway sends one.
    public let preview: String?
    /// A script-only run: there are no messages to open, only `preview`.
    public let isScriptOnly: Bool

    public init(id: String, started: Date, status: Status, preview: String? = nil, isScriptOnly: Bool = false) {
        self.id = id
        self.started = started
        self.status = status
        self.preview = preview
        self.isScriptOnly = isScriptOnly
    }

    /// Reads one row. Session rows and `cron_output` rows share the session list's shape.
    init?(row: JSONValue) {
        guard let id = row["id"]?.stringValue, let started = Self.seconds(row["started_at"]) else { return nil }
        let preview = row["preview"]?.stringValue?.nonBlank
        if id.hasPrefix("cron_output:") || row["source"]?.stringValue == "cron_output" {
            // The title leads with the ledger's status: "FAILED · error", "COMPLETED · preview".
            let title = row["title"]?.stringValue ?? ""
            let label = title.components(separatedBy: " · ").first?.uppercased() ?? ""
            let status: Status = ["FAILED", "ERROR"].contains(label) ? .failed : .finished
            self.init(id: id, started: started, status: status, preview: preview, isScriptOnly: true)
            return
        }
        let status: Status
        if row["ended_at"] == nil || row["ended_at"] == .null {
            let live = row["is_active"]?.boolValue == true || row["scheduler_owned"]?.boolValue == true
            status = live ? .running : .incomplete
        } else {
            status = row["end_reason"]?.stringValue == "cron_incomplete_no_output" ? .incomplete : .finished
        }
        self.init(id: id, started: started, status: status, preview: preview)
    }

    private static func seconds(_ value: JSONValue?) -> Date? {
        if case .number(let seconds) = value { return Date(timeIntervalSince1970: seconds) }
        return nil
    }
}

extension HistoryMessage {
    /// A stored message from `/api/sessions/{id}/messages`: the database row, not `session.resume`'s
    /// projection, so the text is `content` and a tool's name is `tool_name`.
    init?(storedRow row: JSONValue) {
        guard let role = row["role"]?.stringValue, row["display_kind"]?.stringValue != "hidden" else { return nil }
        let timestamp: Double? = {
            if case .number(let seconds) = row["timestamp"] { return seconds }
            return nil
        }()
        self.init(
            role: role, text: row["display_content"]?.stringValue ?? row["content"]?.stringValue,
            name: row["tool_name"]?.stringValue, toolCallId: row["tool_call_id"]?.stringValue, timestamp: timestamp,
            displayKind: row["display_kind"]?.stringValue)
    }
}
