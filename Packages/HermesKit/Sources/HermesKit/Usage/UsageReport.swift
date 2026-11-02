import Foundation

/// One Bot's token use over a period, from the dashboard's `GET /api/analytics/usage`.
///
/// Hermes counts the Bot's own model per session (`daily`, `totals`) and the side models it calls
/// on the side (shortening chats, naming them, reading images…) only in `by_task`, so the two add up
/// without overlap. Every session is filed under the day it started.
public struct UsageReport: Equatable, Sendable {
    public struct Tokens: Equatable, Sendable {
        /// Sent to the model for the first time: messages, tool results.
        public var fresh: Int
        /// Sent again from the provider's cache: the chat so far and the Bot's instructions.
        public var reused: Int
        public var written: Int
        /// The part of `written` the model spent thinking.
        public var thinking: Int

        public init(fresh: Int = 0, reused: Int = 0, written: Int = 0, thinking: Int = 0) {
            self.fresh = fresh
            self.reused = reused
            self.written = written
            self.thinking = thinking
        }

        public var total: Int { fresh + reused + written }

        static func + (lhs: Tokens, rhs: Tokens) -> Tokens {
            Tokens(
                fresh: lhs.fresh + rhs.fresh, reused: lhs.reused + rhs.reused, written: lhs.written + rhs.written,
                thinking: lhs.thinking + rhs.thinking)
        }
    }

    public struct Day: Equatable, Sendable, Identifiable {
        /// The start of the day, in this device's calendar.
        public let date: Date
        public var tokens: Tokens
        public var id: Date { date }
    }

    /// Work a side model did beside the chats, such as `compression` or `title_generation`.
    public struct BackgroundJob: Equatable, Sendable, Identifiable {
        public let name: String
        /// Read and written; Hermes doesn't split these out by day or by cache.
        public var tokens: Int
        public var calls: Int
        public var id: String { name }
    }

    /// What it cost, when Hermes knows: the provider's bill, or else Hermes's estimate from its
    /// price list. Models without a price count as nothing.
    public struct Cost: Equatable, Sendable {
        public var amount: Double
        public var isEstimate: Bool
    }

    public var days: [Day]
    /// The Bot's own model, in every session: chats, rooms, routines and helpers it starts.
    public var main: Tokens
    public var jobs: [BackgroundJob]
    public var calls: Int
    public var cost: Cost?

    public init(
        days: [Day] = [], main: Tokens = Tokens(), jobs: [BackgroundJob] = [], calls: Int = 0, cost: Cost? = nil
    ) {
        self.days = days
        self.main = main
        self.jobs = jobs
        self.calls = calls
        self.cost = cost
    }

    public var totalTokens: Int { main.total + jobs.reduce(0) { $0 + $1.tokens } }

    public var isEmpty: Bool { totalTokens == 0 && calls == 0 }

    /// Reads the route's answer. Fields an older Hermes doesn't send (`by_task`, cache and thinking
    /// counts) count as zero; `SUM` over no sessions arrives as `null`.
    init(json: JSONValue, calendar: Calendar = .current) throws {
        guard case .object = json, let totals = json["totals"], case .object = totals else {
            throw GatewayError.invalidResponse
        }
        main = Tokens(
            fresh: Self.count(totals["total_input"]), reused: Self.count(totals["total_cache_read"]),
            written: Self.count(totals["total_output"]), thinking: Self.count(totals["total_reasoning"]))
        calls = Self.count(totals["total_api_calls"])
        var days: [Day] = []
        if case .array(let rows) = json["daily"] {
            for row in rows {
                guard let label = row["day"]?.stringValue, let date = Self.day(label, calendar: calendar) else {
                    continue
                }
                days.append(
                    Day(
                        date: date,
                        tokens: Tokens(
                            fresh: Self.count(row["input_tokens"]), reused: Self.count(row["cache_read_tokens"]),
                            written: Self.count(row["output_tokens"]), thinking: Self.count(row["reasoning_tokens"]))))
            }
        }
        self.days = days.sorted { $0.date < $1.date }
        var jobCost = 0.0
        var jobs: [BackgroundJob] = []
        if case .array(let rows) = json["by_task"] {
            for row in rows {
                guard let name = row["task"]?.stringValue, !name.isEmpty else { continue }
                jobCost += Self.amount(row["estimated_cost"])
                jobs.append(
                    BackgroundJob(
                        name: name, tokens: Self.count(row["input_tokens"]) + Self.count(row["output_tokens"]),
                        calls: Self.count(row["api_calls"])))
            }
        }
        self.jobs = jobs.sorted { $0.tokens > $1.tokens }
        let billed = Self.amount(totals["total_actual_cost"])
        let estimated = Self.amount(totals["total_estimated_cost"])
        let amount = (billed > 0 ? billed : estimated) + jobCost
        cost = amount > 0 ? Cost(amount: amount, isEstimate: billed == 0 || jobCost > 0) : nil
    }

    /// Several Bots' reports as one: days and background work added up by day and by name.
    public static func combined(_ reports: [UsageReport]) -> UsageReport {
        var days: [Date: Tokens] = [:]
        var jobs: [String: BackgroundJob] = [:]
        var result = UsageReport()
        for report in reports {
            for day in report.days {
                days[day.date, default: Tokens()] = days[day.date, default: Tokens()] + day.tokens
            }
            for job in report.jobs {
                var merged = jobs[job.name] ?? BackgroundJob(name: job.name, tokens: 0, calls: 0)
                merged.tokens += job.tokens
                merged.calls += job.calls
                jobs[job.name] = merged
            }
            result.main = result.main + report.main
            result.calls += report.calls
            if let cost = report.cost {
                result.cost = Cost(
                    amount: (result.cost?.amount ?? 0) + cost.amount,
                    isEstimate: (result.cost?.isEstimate ?? false) || cost.isEstimate)
            }
        }
        result.days = days.map { Day(date: $0.key, tokens: $0.value) }.sorted { $0.date < $1.date }
        result.jobs = jobs.values.sorted { ($0.tokens, $1.name) > ($1.tokens, $0.name) }
        return result
    }

    /// One entry for every day of the last `count` days up to `today`, with nothing used on days
    /// Hermes didn't list. The window starts part-way through a day, so an earlier listed day stays.
    public func daily(last count: Int, until today: Date, calendar: Calendar = .current) -> [Day] {
        let end = calendar.startOfDay(for: today)
        guard var day = calendar.date(byAdding: .day, value: -(max(count, 1) - 1), to: end) else { return days }
        if let first = days.first?.date, first < day { day = first }
        let listed = Dictionary(days.map { ($0.date, $0.tokens) }, uniquingKeysWith: +)
        var filled: [Day] = []
        while day <= end {
            filled.append(Day(date: day, tokens: listed[day] ?? Tokens()))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return filled
    }

    /// `2026-11-02`, the gateway's own calendar day, read as that day here.
    private static func day(_ label: String, calendar: Calendar) -> Date? {
        let parts = label.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func count(_ value: JSONValue?) -> Int {
        guard case .number(let number)? = value, number.isFinite, number > 0 else { return 0 }
        return Int(number.rounded())
    }

    private static func amount(_ value: JSONValue?) -> Double {
        guard case .number(let number)? = value, number.isFinite, number > 0 else { return 0 }
        return number
    }
}
