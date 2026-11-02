import Foundation

/// Routine schedules in plain words, and the common ones as choices that write a cron expression.
public enum RoutineSchedule {
    /// The choices the When picker offers, as the official Hermes app does.
    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case daily, weekdays, weekly, monthly, hourly, every15Minutes, custom

        public var id: Self { self }

        /// Whether a time of day goes with it.
        public var hasTime: Bool { [.daily, .weekdays, .weekly, .monthly].contains(self) }
    }

    /// A preset with its time, read from or written as a cron expression.
    public struct Choice: Equatable, Sendable {
        public var preset: Preset
        public var hour: Int
        public var minute: Int
        /// 0 is Sunday, as in cron. Weekly only.
        public var weekday: Int

        public init(preset: Preset, hour: Int = 9, minute: Int = 0, weekday: Int = 1) {
            self.preset = preset
            self.hour = hour
            self.minute = minute
            self.weekday = weekday
        }

        /// The cron expression the gateway stores, or `nil` for Custom.
        public var expression: String? {
            switch preset {
            case .daily: "\(minute) \(hour) * * *"
            case .weekdays: "\(minute) \(hour) * * 1-5"
            case .weekly: "\(minute) \(hour) * * \(weekday)"
            case .monthly: "\(minute) \(hour) 1 * *"
            case .hourly: "0 * * * *"
            case .every15Minutes: "*/15 * * * *"
            case .custom: nil
            }
        }

        /// The preset `text` is, or Custom with nine o'clock Monday for anything else.
        public init(_ text: String) {
            self.init(preset: .custom)
            guard let cron = Cron(text) else { return }
            switch (cron.minute, cron.hour, cron.day, cron.weekday) {
            case ("0", "*", "*", "*"): preset = .hourly
            case ("*/15", "*", "*", "*"): preset = .every15Minutes
            default:
                guard let minute = Int(cron.minute), let hour = Int(cron.hour), (0..<60).contains(minute),
                    (0..<24).contains(hour)
                else { return }
                switch (cron.day, cron.weekday) {
                case ("*", "*"): preset = .daily
                case ("*", "1-5"): preset = .weekdays
                case ("1", "*"): preset = .monthly
                case ("*", let day):
                    guard let day = Cron.weekday(day) else { return }
                    preset = .weekly
                    weekday = day
                default: return
                }
                self.hour = hour
                self.minute = minute
            }
        }
    }

    /// "Weekdays at 9:00 AM" for "0 9 * * 1-5", "Every 2 hours" for "every 120m". Phrases the
    /// gateway kept as typed, like "every monday 9am", come back capitalised.
    public static func plainWords(_ schedule: String, locale: Locale = .current) -> String {
        let text = schedule.trimmingCharacters(in: .whitespaces)
        if let minutes = intervalMinutes(text) { return interval(minutes) }
        if let cron = Cron(text), let words = cron.words(locale: locale) { return words }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The minutes in the gateway's interval display, "every 120m".
    private static func intervalMinutes(_ text: String) -> Int? {
        guard let match = text.wholeMatch(of: /every (\d+)m/) else { return nil }
        return Int(match.1)
    }

    private static func interval(_ minutes: Int) -> String {
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return days == 1 ? String(localized: "Every day") : String(localized: "Every \(days) days")
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? String(localized: "Every hour") : String(localized: "Every \(hours) hours")
        }
        return minutes == 1 ? String(localized: "Every minute") : String(localized: "Every \(minutes) minutes")
    }

    static func time(hour: Int, minute: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute))!
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// The day names cron's 0–6 stand for, Sunday first.
    public static func weekdayName(_ day: Int, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.weekdaySymbols[day % 7]
    }
}

/// The five fields of a cron expression.
private struct Cron {
    let minute, hour, day, month, weekday: String

    init?(_ text: String) {
        let fields = text.split(separator: " ").map(String.init)
        guard fields.count == 5, fields.allSatisfy({ $0.wholeMatch(of: /[A-Za-z\d*\-,\/]+/) != nil }) else {
            return nil
        }
        (minute, hour, day, month, weekday) = (fields[0], fields[1], fields[2], fields[3], fields[4])
    }

    static func weekday(_ field: String) -> Int? {
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if let index = names.firstIndex(of: field.lowercased()) { return index }
        guard let day = Int(field), (0...7).contains(day) else { return nil }
        return day % 7
    }

    func words(locale: Locale) -> String? {
        guard month == "*" else { return nil }
        if hour == "*", day == "*", weekday == "*" {
            if minute == "0" { return String(localized: "Every hour") }
            if let step = minute.wholeMatch(of: /\*\/(\d+)/).flatMap({ Int($0.1) }) {
                return String(localized: "Every \(step) minutes")
            }
            return nil
        }
        if minute == "0", day == "*", weekday == "*",
            let step = hour.wholeMatch(of: /\*\/(\d+)/).flatMap({ Int($0.1) })
        {
            return String(localized: "Every \(step) hours")
        }
        guard let m = Int(minute), let h = Int(hour), (0..<60).contains(m), (0..<24).contains(h) else { return nil }
        let time = RoutineSchedule.time(hour: h, minute: m, locale: locale)
        switch (day, weekday) {
        case ("*", "*"): return String(localized: "Every day at \(time)")
        case ("*", "1-5"), ("*", "mon-fri"), ("*", "MON-FRI"): return String(localized: "Weekdays at \(time)")
        case ("*", "0,6"), ("*", "6,0"), ("*", "sat,sun"), ("*", "SAT,SUN"):
            return String(localized: "Weekends at \(time)")
        case ("*", let field):
            guard let index = Cron.weekday(field) else { return nil }
            return String(localized: "Every \(RoutineSchedule.weekdayName(index, locale: locale)) at \(time)")
        case (let field, "*"):
            guard let date = Int(field), (1...31).contains(date) else { return nil }
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .ordinal
            let ordinal = formatter.string(from: date as NSNumber) ?? field
            return String(localized: "Monthly on the \(ordinal) at \(time)")
        default: return nil
        }
    }
}
