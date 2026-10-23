import Foundation

/// A scheduled job an agent runs on its own (a Hermes cron job).
public struct Routine: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// How the gateway describes the schedule, e.g. "every monday at 9am" or "0 9 * * 1".
    public let schedule: String
    /// Runs on schedule; `false` while paused.
    public let isOn: Bool
    /// Finished for good, e.g. a one-off that already ran.
    public let isFinished: Bool
    public let nextRun: Date?
    public let lastRun: Date?
    /// The last run failed.
    public let lastRunFailed: Bool

    public init(
        id: String, name: String, schedule: String, isOn: Bool, isFinished: Bool = false, nextRun: Date? = nil,
        lastRun: Date? = nil, lastRunFailed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.isOn = isOn
        self.isFinished = isFinished
        self.nextRun = nextRun
        self.lastRun = lastRun
        self.lastRunFailed = lastRunFailed
    }

    /// Reads one job from `/api/cron/jobs`. Returns `nil` for anything without an ID.
    init?(job: JSONValue) {
        guard let id = job["id"]?.stringValue else { return nil }
        let state = job["state"]?.stringValue
        self.init(
            id: id,
            name: job["name"]?.stringValue?.nonBlank ?? job["prompt"]?.stringValue?.nonBlank ?? id,
            schedule: job["schedule_display"]?.stringValue?.nonBlank ?? job["schedule"]?["display"]?.stringValue
                ?? job["schedule"]?["expr"]?.stringValue ?? "",
            isOn: job["enabled"]?.boolValue != false && state != "paused",
            isFinished: state == "completed",
            nextRun: job["next_run_at"]?.stringValue.flatMap(Self.date),
            lastRun: job["last_run_at"]?.stringValue.flatMap(Self.date),
            lastRunFailed: ["error", "failed"].contains(job["last_status"]?.stringValue ?? "") || state == "error")
    }

    /// Python's `isoformat()`: an offset is always present here, microseconds sometimes.
    static func date(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return try? Date(trimmed, strategy: .iso8601)
    }
}
