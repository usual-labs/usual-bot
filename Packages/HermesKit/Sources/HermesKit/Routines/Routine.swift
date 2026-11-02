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
    /// What the agent is asked to do each time.
    public let prompt: String
    /// Where the output goes, as the gateway stores it: `local`, `bot-chat:<profile>`, `telegram`…
    public let deliver: String
    /// The schedule as text the gateway reads back the same way, for editing.
    public let scheduleText: String
    /// Why the last run failed, in the gateway's words.
    public let lastError: String?
    /// Runs a script or skills, so it needs no prompt of its own.
    public let worksWithoutPrompt: Bool
    /// Why the last run's result couldn't be posted where it goes, in the gateway's words. The run
    /// itself may have worked.
    public let deliveryError: String?

    public init(
        id: String, name: String, schedule: String, isOn: Bool, isFinished: Bool = false, nextRun: Date? = nil,
        lastRun: Date? = nil, lastRunFailed: Bool = false, prompt: String = "", deliver: String = "local",
        scheduleText: String? = nil, lastError: String? = nil, worksWithoutPrompt: Bool = false,
        deliveryError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.isOn = isOn
        self.isFinished = isFinished
        self.nextRun = nextRun
        self.lastRun = lastRun
        self.lastRunFailed = lastRunFailed
        self.prompt = prompt
        self.deliver = deliver
        self.scheduleText = scheduleText ?? schedule
        self.lastError = lastError
        self.worksWithoutPrompt = worksWithoutPrompt
        self.deliveryError = deliveryError
    }

    /// Reads one job from `/api/cron/jobs`. Returns `nil` for anything without an ID.
    init?(job: JSONValue) {
        guard let id = job["id"]?.stringValue else { return nil }
        let state = job["state"]?.stringValue
        let display =
            job["schedule_display"]?.stringValue?.nonBlank ?? job["schedule"]?["display"]?.stringValue
            ?? job["schedule"]?["expr"]?.stringValue ?? ""
        // A one-off's display ("once at 2026-11-02 09:00") doesn't parse again; its time does.
        let editable =
            job["schedule"]?["kind"]?.stringValue == "once"
            ? job["schedule"]?["run_at"]?.stringValue ?? display : display
        let hasSkills: Bool = {
            if case .array(let skills) = job["skills"] { return !skills.isEmpty }
            return job["skill"]?.stringValue?.nonBlank != nil
        }()
        let failed = ["error", "failed"].contains(job["last_status"]?.stringValue ?? "") || state == "error"
        self.init(
            id: id,
            name: job["name"]?.stringValue?.nonBlank ?? job["prompt"]?.stringValue?.nonBlank ?? id,
            schedule: display,
            isOn: job["enabled"]?.boolValue != false && state != "paused",
            isFinished: state == "completed",
            nextRun: job["next_run_at"]?.stringValue.flatMap(Self.date),
            lastRun: job["last_run_at"]?.stringValue.flatMap(Self.date),
            lastRunFailed: failed,
            prompt: job["prompt"]?.stringValue ?? "",
            deliver: Self.deliverText(job["deliver"]),
            scheduleText: editable,
            lastError: failed ? job["last_error"]?.stringValue?.nonBlank : nil,
            worksWithoutPrompt: hasSkills || job["script"]?.stringValue?.nonBlank != nil,
            deliveryError: job["last_delivery_error"]?.stringValue?.nonBlank)
    }

    /// Python's `isoformat()`: an offset is always present here, microseconds sometimes.
    static func date(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return try? Date(trimmed, strategy: .iso8601)
    }

    /// Hand-edited jobs may hold a list of targets instead of one comma-separated string.
    private static func deliverText(_ value: JSONValue?) -> String {
        switch value {
        case .string(let text): return text.nonBlank ?? "local"
        case .array(let parts): return parts.compactMap(\.stringValue).joined(separator: ",").nonBlank ?? "local"
        default: return "local"
        }
    }
}

/// Where a routine's output goes, in the two choices Usual Bot offers and everything else.
public enum RoutineDelivery: Hashable, Sendable {
    /// Posted into the agent's Bot Chat, the chat Usual Bot shows. The agent reads it and replies.
    case thisChat
    /// Kept only in the routine's past runs.
    case pastRunsOnly
    /// Somewhere Usual Bot doesn't set up itself, like Telegram, kept as the gateway has it.
    case elsewhere(String)

    public init(deliver: String, profile: String) {
        let value = deliver.trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "", "local": self = .pastRunsOnly
        case "bot-chat", "bot-chat:\(profile.lowercased())": self = .thisChat
        default: self = .elsewhere(deliver)
        }
    }

    /// What the gateway stores for this choice.
    public func value(profile: String) -> String {
        switch self {
        case .thisChat: "bot-chat:\(profile)"
        case .pastRunsOnly: "local"
        case .elsewhere(let raw): raw
        }
    }

    /// "Telegram and Discord": the places a raw `deliver` names, for saying where output goes.
    public static func places(_ deliver: String, profile: String) -> String {
        let names = deliver.split(separator: ",").map { part -> String in
            let token = part.trimmingCharacters(in: .whitespaces)
            switch RoutineDelivery(deliver: token, profile: profile) {
            case .thisChat: return String(localized: "this chat")
            case .pastRunsOnly: return String(localized: "past runs")
            case .elsewhere:
                let platform = token.split(separator: ":").first.map(String.init) ?? token
                switch platform.lowercased() {
                case "origin": return String(localized: "the chat it was set up from")
                case "all": return String(localized: "every connected app")
                case "bot-chat":
                    let other = token.dropFirst("bot-chat:".count)
                    return String(localized: "\(String(other))'s chat")
                default: return platform.prefix(1).uppercased() + platform.dropFirst()
                }
            }
        }
        return names.formatted(.list(type: .and))
    }
}

/// What the New Routine and Edit forms hold.
public struct RoutineDraft: Equatable, Sendable {
    public var name: String
    /// What to do each time.
    public var prompt: String
    /// When, as text the gateway parses: "every day at 9am", "0 9 * * 1-5", "every 2h".
    public var schedule: String
    public var delivery: RoutineDelivery

    public init(name: String = "", prompt: String = "", schedule: String = "", delivery: RoutineDelivery = .thisChat) {
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.delivery = delivery
    }

    /// A form filled with `routine` as it is.
    public init(_ routine: Routine, profile: String) {
        self.init(
            name: routine.name, prompt: routine.prompt, schedule: routine.scheduleText,
            delivery: RoutineDelivery(deliver: routine.deliver, profile: profile))
    }

    /// Something to do and a time to do it. An existing routine that runs a script or skills
    /// may have no prompt.
    public func isComplete(editing routine: Routine? = nil) -> Bool {
        guard schedule.nonBlank != nil else { return false }
        return prompt.nonBlank != nil || routine?.worksWithoutPrompt == true
    }

    /// The body for `POST /api/cron/jobs`. A blank name lets the gateway name it from the prompt.
    func createBody(profile: String) -> JSONValue {
        [
            "name": .string(name.trimmed), "prompt": .string(prompt.trimmed), "schedule": .string(schedule.trimmed),
            "deliver": .string(delivery.value(profile: profile)),
        ]
    }

    /// The `updates` for `PUT /api/cron/jobs/{id}`: only what changed, so an unchanged schedule
    /// keeps its next run and other settings the form doesn't show stay as they are.
    func updates(from routine: Routine, profile: String) -> JSONValue {
        var updates: [String: JSONValue] = [:]
        if let name = name.nonBlank, name.trimmed != routine.name { updates["name"] = .string(name.trimmed) }
        if prompt.trimmed != routine.prompt.trimmed { updates["prompt"] = .string(prompt.trimmed) }
        if schedule.trimmed != routine.scheduleText.trimmed { updates["schedule"] = .string(schedule.trimmed) }
        let deliver = delivery.value(profile: profile)
        if delivery != RoutineDelivery(deliver: routine.deliver, profile: profile) {
            updates["deliver"] = .string(deliver)
        }
        return .object(updates)
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
