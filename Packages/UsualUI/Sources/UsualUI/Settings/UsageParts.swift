import Charts
import HermesKit
import SwiftUI

/// The three kinds of tokens the Bot's own model handles, in the order they stack in the chart.
enum UsageKind: CaseIterable, Identifiable {
    case written, fresh, reused
    var id: Self { self }

    var title: String {
        switch self {
        case .written: String(localized: "Written")
        case .fresh: String(localized: "Sent new")
        case .reused: String(localized: "Sent again")
        }
    }

    var detail: String {
        switch self {
        case .written: String(localized: "Replies, tool calls and thinking.")
        case .fresh: String(localized: "Your messages, tool results and anything sent for the first time.")
        case .reused:
            String(
                localized:
                    "The chat so far and the Bot's instructions, sent again with each step. Providers charge less for it."
            )
        }
    }

    /// The first three slots of a palette checked for colour blindness, stepped for each mode.
    var color: Color {
        switch self {
        case .reused: Color(light: 0x2A78D6, dark: 0x3987E5)
        case .fresh: Color(light: 0xEB6834, dark: 0xD95926)
        case .written: Color(light: 0x1BAF7A, dark: 0x199E70)
        }
    }

    func count(_ tokens: UsageReport.Tokens) -> Int {
        switch self {
        case .written: tokens.written
        case .fresh: tokens.fresh
        case .reused: tokens.reused
        }
    }
}

extension UsageOverview.Period {
    var title: String {
        switch self {
        case .week: String(localized: "7 Days")
        case .month: String(localized: "30 Days")
        case .quarter: String(localized: "90 Days")
        }
    }
}

extension UsageReport.BackgroundJob {
    /// Hermes's names for its side models' jobs (`auxiliary` tasks), in words.
    var title: String {
        switch name {
        case "compression": String(localized: "Shortening long chats")
        case "title_generation": String(localized: "Naming chats")
        case "vision": String(localized: "Looking at images")
        case "session_search": String(localized: "Searching past chats")
        case "web_extract": String(localized: "Reading web pages")
        case "approval": String(localized: "Checking commands before they run")
        case "background_review": String(localized: "Deciding what to remember")
        case "moa_reference": String(localized: "Asking other models")
        case "moa_aggregator": String(localized: "Combining other models' answers")
        case "mcp": String(localized: "Requests from apps")
        default: name.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }
}

enum UsageFormat {
    static func tokens(_ count: Int) -> String { ChatThread.tokens(count) }

    static func cost(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(amount < 1 ? 2...3 : 2...2)))
    }

    static func share(_ part: Int, of whole: Int) -> Double { whole > 0 ? Double(part) / Double(whole) : 0 }

    /// `12%`, or `<1%` for a sliver that isn't nothing.
    static func percent(_ share: Double) -> String {
        if share > 0, share < 0.005 { return String(localized: "<1%") }
        return share.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Tokens, cost when Hermes knows it, and model calls, side by side.
struct UsageTotals: View {
    let report: UsageReport

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            stat(String(localized: "Tokens"), UsageFormat.tokens(report.totalTokens), nil)
            if let cost = report.cost {
                stat(
                    String(localized: "Cost"), UsageFormat.cost(cost.amount),
                    cost.isEstimate ? String(localized: "Hermes's estimate") : String(localized: "From the provider"))
            }
            stat(String(localized: "Model calls"), report.calls.formatted(), nil)
        }
        .padding(.vertical, 4)
    }

    private func stat(_ label: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.secondaryInk)
            Text(value).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink).monospacedDigit()
            if let note { Text(note).font(.caption2).foregroundStyle(Theme.secondaryInk) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Tokens per day, stacked by kind. Background work has no days, so it isn't here.
struct UsageChart: View {
    let report: UsageReport
    let period: UsageOverview.Period
    let today: Date

    var body: some View {
        let days = report.daily(last: period.rawValue, until: today)
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(days) { day in
                    ForEach(UsageKind.allCases) { kind in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Tokens", kind.count(day.tokens))
                        )
                        .foregroundStyle(by: .value("Kind", kind.title))
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .accessibilityValue("\(kind.title): \(UsageFormat.tokens(kind.count(day.tokens))) tokens")
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: UsageKind.allCases.map(\.title), range: UsageKind.allCases.map(\.color)
            )
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: xValues) { _ in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel(format: xFormat).foregroundStyle(Theme.secondaryInk)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text(UsageFormat.tokens(count)).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityLabel(Text("Tokens per day"))
            if let busiest = days.max(by: { $0.tokens.total < $1.tokens.total }), busiest.tokens.total > 0 {
                Text(
                    "Busiest day: \(busiest.date.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(UsageFormat.tokens(busiest.tokens.total)) tokens."
                )
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.vertical, 6)
    }

    private var xValues: AxisMarkValues {
        switch period {
        case .week: .stride(by: .day)
        case .month: .stride(by: .day, count: 7)
        case .quarter: .stride(by: .month)
        }
    }

    private var xFormat: Date.FormatStyle {
        switch period {
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.day().month(.abbreviated)
        case .quarter: .dateTime.month(.abbreviated)
        }
    }
}

/// Where a report's tokens went, largest first: the Bot's own reading and writing, then each kind
/// of background work. Also the chart's numbers as text.
struct UsageBreakdown: View {
    let report: UsageReport

    var body: some View {
        let total = report.totalTokens
        let kinds = UsageKind.allCases.map { kind in
            Row(
                id: "\(kind)", title: kind.title, detail: detail(kind), tokens: kind.count(report.main),
                color: kind.color)
        }
        let jobs = report.jobs.map { job in
            Row(id: job.name, title: job.title, detail: nil, tokens: job.tokens, color: Theme.secondaryInk)
        }
        ForEach((kinds + jobs).filter { $0.tokens > 0 }.sorted { $0.tokens > $1.tokens }) { row in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).foregroundStyle(Theme.ink)
                        if let detail = row.detail {
                            Text(detail).font(.caption).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    Spacer(minLength: 12)
                    let share = UsageFormat.share(row.tokens, of: total)
                    Text(
                        "\(UsageFormat.tokens(row.tokens)) · \(UsageFormat.percent(share))"
                    )
                    .foregroundStyle(Theme.secondaryInk)
                    .monospacedDigit()
                }
                ShareBar(fraction: UsageFormat.share(row.tokens, of: total), color: row.color)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    private func detail(_ kind: UsageKind) -> String {
        guard kind == .written, report.main.thinking > 0 else { return kind.detail }
        return kind.detail + " "
            + String(localized: "\(UsageFormat.tokens(report.main.thinking)) of it was thinking.")
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let detail: String?
        let tokens: Int
        let color: Color
    }
}

/// A thin bar filled to `fraction`.
struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(Theme.selection)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule().fill(color).frame(width: max(3, geometry.size.width * min(max(fraction, 0), 1)))
                }
            }
            .accessibilityHidden(true)
    }
}
