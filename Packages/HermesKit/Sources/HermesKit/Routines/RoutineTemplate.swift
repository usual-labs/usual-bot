import Foundation

/// A fill-in routine from the gateway's `/api/cron/blueprints` (Hermes calls them blueprints): a
/// title, a line about it, and the fields to fill. Hermes keeps the prompt and the skills it
/// loads to itself and fills them in when `POST /api/cron/blueprints/instantiate` creates the
/// routine, so the app sees those only once the routine exists.
public struct RoutineTemplate: Identifiable, Equatable, Sendable {
    public struct Field: Identifiable, Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// "HH:MM", 24-hour.
            case time
            /// One of `options`.
            case choice
            case text
            /// `everyday`, `weekdays` or `weekends`.
            case days
        }

        public let name: String
        public let kind: Kind
        /// The question as Hermes words it, like "What time?" or "Remind me to…".
        public let label: String
        public let defaultValue: String
        public let options: [String]
        public let isOptional: Bool
        /// `false` when `options` are suggestions and any value goes.
        public let isStrict: Bool
        public let help: String

        public var id: String { name }

        /// Where results go. The form shows the app's own Results choice for it.
        public var isDelivery: Bool { name == RoutineTemplate.deliveryField }

        public init(
            name: String, kind: Kind, label: String, defaultValue: String = "", options: [String] = [],
            isOptional: Bool = false, isStrict: Bool = true, help: String = ""
        ) {
            self.name = name
            self.kind = kind
            self.label = label
            self.defaultValue = defaultValue
            self.options = options
            self.isOptional = isOptional
            self.isStrict = isStrict
            self.help = help
        }

        /// A choice in words: "Every day" for `everyday`, "Sunday" for `sunday`, else capitalised.
        public func title(for option: String, locale: Locale = .current) -> String {
            switch option.lowercased() {
            case "everyday": return String(localized: "Every day")
            case "weekdays": return String(localized: "Weekdays")
            case "weekends": return String(localized: "Weekends")
            default:
                if let day = RoutineTemplate.weekdays[option.lowercased()] {
                    return RoutineSchedule.weekdayName(day, locale: locale)
                }
                return option.prefix(1).uppercased() + option.dropFirst()
            }
        }

        /// Why `value` won't do, or `nil` when it's fine. Mirrors Hermes's `fill_blueprint` so the
        /// form can say it before anything is sent.
        public func problem(with value: String) -> String? {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { return isOptional ? nil : String(localized: "Fill this in.") }
            switch kind {
            case .time:
                if RoutineTemplate.hourAndMinute(value) == nil {
                    return String(localized: "Use a time like 08:00.")
                }
            case .choice, .days:
                if isStrict, !options.isEmpty, !options.contains(value) {
                    return String(localized: "Pick one of the choices.")
                }
            case .text: break
            }
            return nil
        }
    }

    public let key: String
    public let title: String
    /// One line about what it does.
    public let summary: String
    /// `daily`, `weekly`, `email`, `general`… Plugins may add their own.
    public let category: String
    public let fields: [Field]
    /// A cron expression with `{field}` placeholders, like `{minute} {hour} * * {dow}`.
    public let scheduleTemplate: String

    public var id: String { key }

    public init(
        key: String, title: String, summary: String, category: String = "general", fields: [Field],
        scheduleTemplate: String
    ) {
        self.key = key
        self.title = title
        self.summary = summary
        self.category = category
        self.fields = fields
        self.scheduleTemplate = scheduleTemplate
    }

    /// Reads one entry of `/api/cron/blueprints`. `nil` without a key, a title or a schedule.
    init?(entry: JSONValue) {
        guard let key = entry["key"]?.stringValue?.nonBlank, let title = entry["title"]?.stringValue?.nonBlank,
            let schedule = entry["schedule"]?.stringValue?.nonBlank
        else { return nil }
        var fields: [Field] = []
        if case .array(let rows) = entry["fields"] {
            for row in rows {
                guard let name = row["name"]?.stringValue?.nonBlank else { continue }
                let kind: Field.Kind =
                    switch row["type"]?.stringValue {
                    case "time": .time
                    case "enum": .choice
                    case "weekdays": .days
                    default: .text
                    }
                var options: [String] = []
                if case .array(let values) = row["options"] { options = values.compactMap(Self.text) }
                fields.append(
                    Field(
                        name: name, kind: kind, label: row["label"]?.stringValue?.nonBlank ?? name,
                        defaultValue: row["default"].flatMap(Self.text) ?? "", options: options,
                        isOptional: row["optional"]?.boolValue ?? false, isStrict: row["strict"]?.boolValue ?? true,
                        help: row["help"]?.stringValue ?? ""))
            }
        }
        self.init(
            key: key, title: title, summary: entry["description"]?.stringValue ?? "",
            category: entry["category"]?.stringValue ?? "general", fields: fields, scheduleTemplate: schedule)
    }

    /// The catalog in `{"blueprints": [...]}`, skipping entries it can't read.
    static func catalog(_ page: JSONValue) throws -> [RoutineTemplate] {
        guard case .array(let rows) = page["blueprints"] else { throw GatewayError.invalidResponse }
        return rows.compactMap(RoutineTemplate.init(entry:))
    }

    /// The fields the form asks: all but where results go, which the Results choice covers.
    public var questions: [Field] { fields.filter { !$0.isDelivery } }

    /// Whether it asks where results go.
    public var hasDelivery: Bool { fields.contains(where: \.isDelivery) }

    /// Each field's starting value.
    public var defaults: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.defaultValue) })
    }

    /// Whether every question has a value Hermes takes.
    public func isComplete(_ values: [String: String]) -> Bool {
        questions.allSatisfy { $0.problem(with: values[$0.name] ?? "") == nil } && schedule(values) != nil
    }

    /// The `values` for instantiate: each field's trimmed value, blank optional ones left out, and
    /// where results go as the app's choice. Fields the template doesn't have are never sent: Hermes
    /// refuses unknown ones.
    func filled(_ values: [String: String], delivery: RoutineDelivery, profile: String) -> [String: String] {
        var filled: [String: String] = [:]
        for field in fields {
            let value =
                field.isDelivery
                ? delivery.value(profile: profile)
                : (values[field.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { filled[field.name] = value }
        }
        return filled
    }

    /// The cron expression Hermes will store for `values`, worked out the way its
    /// `_resolve_schedule` does, or `nil` when a value it needs is missing or wrong.
    public func schedule(_ values: [String: String]) -> String? {
        let values = values.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.value.isEmpty
        }
        if let verbatim = values["schedule"] { return verbatim }
        var parts = values
        if scheduleTemplate.contains("{minute}") || scheduleTemplate.contains("{hour}") {
            guard let time = values["time"], let (hour, minute) = Self.hourAndMinute(time) else { return nil }
            parts["hour"] = String(hour)
            parts["minute"] = String(minute)
        }
        if scheduleTemplate.contains("{dow}") {
            if let preset = values["recurrence"] {
                guard let days = Self.dayPresets[preset.lowercased()] else { return nil }
                parts["dow"] = days
            } else if let day = values["day"] {
                guard let number = Self.weekdays[day.lowercased()] else { return nil }
                parts["dow"] = String(number)
            } else {
                parts["dow"] = "*"
            }
        }
        if scheduleTemplate.contains("{interval_min}") {
            guard let minutes = values["interval_min"].flatMap({ Int($0) }), minutes > 0 else { return nil }
        }
        return Self.fill(scheduleTemplate, with: parts)
    }

    /// `template` with each `{name}` replaced by its value, or `nil` if one has none.
    public static func fill(_ template: String, with values: [String: String]) -> String? {
        var result = ""
        var rest = template[...]
        while let match = rest.firstMatch(of: /\{(\w+)\}/) {
            guard let value = values[String(match.1)] else { return nil }
            result += rest[..<match.range.lowerBound] + value
            rest = rest[match.range.upperBound...]
        }
        return result + rest
    }

    static let deliveryField = "deliver"

    /// Hermes's `WEEKDAY_PRESETS`.
    static let dayPresets = ["everyday": "*", "weekdays": "1-5", "weekends": "0,6"]

    /// Hermes's `_DAY_TO_DOW`, Sunday as 0.
    static let weekdays = [
        "sunday": 0, "monday": 1, "tuesday": 2, "wednesday": 3, "thursday": 4, "friday": 5, "saturday": 6,
    ]

    /// "08:00" as (8, 0): Hermes's `^([01]?\d|2[0-3]):([0-5]\d)$`.
    static func hourAndMinute(_ text: String) -> (Int, Int)? {
        guard let match = text.wholeMatch(of: /([01]?\d|2[0-3]):([0-5]\d)/),
            let hour = Int(match.1), let minute = Int(match.2)
        else { return nil }
        return (hour, minute)
    }

    /// Plugin templates may give numbers where the built-in ones give text.
    private static func text(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): text
        case .number(let number): number.rounded() == number ? String(Int(number)) : String(number)
        case .bool(let flag): flag ? "true" : "false"
        default: nil
        }
    }
}

/// A routine just made from a template, and the skills it uses that the agent can't load.
public struct TemplateRoutine: Equatable, Sendable {
    /// A skill the routine asks for that won't load when it runs.
    public struct MissingSkill: Equatable, Sendable {
        public let name: String
        /// Installed but turned off for this agent, rather than not there at all.
        public let isOff: Bool

        public init(name: String, isOff: Bool) {
            self.name = name
            self.isOff = isOff
        }
    }

    public let routine: Routine
    /// Hermes skips these with a note in the run and carries on without them.
    public let missingSkills: [MissingSkill]

    public init(routine: Routine, missingSkills: [MissingSkill] = []) {
        self.routine = routine
        self.missingSkills = missingSkills
    }

    /// The skills in `job` that aren't among `installed`, or are turned off there.
    static func missing(in job: JSONValue, installed: [Skill]) -> [MissingSkill] {
        var names: [String] = []
        if case .array(let skills) = job["skills"] { names = skills.compactMap(\.stringValue) }
        if names.isEmpty, let single = job["skill"]?.stringValue { names = [single] }
        return names.compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            guard let skill = installed.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return MissingSkill(name: name, isOff: false)
            }
            return skill.enabled ? nil : MissingSkill(name: name, isOff: true)
        }
    }
}
