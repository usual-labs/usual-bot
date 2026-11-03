import Foundation
import HermesKit
import SwiftUI

/// The dates between messages, as in Grok and Messages: one above the first message, and again
/// after a new day starts or an hour passes without a word.
enum DateLabels {
    static let quietGap: TimeInterval = 3600

    /// The label to show above each item that gets one, by item ID. Items with no date are passed
    /// over, so an old cache without dates shows none.
    static func labels(
        for items: [TranscriptItem], now: Date = .now, calendar: Calendar = .current
    ) -> [Int: String] {
        var labels: [Int: String] = [:]
        var previous: Date?
        for item in items {
            guard let date = item.date else { continue }
            if let previous, calendar.isDate(previous, inSameDayAs: date), date.timeIntervalSince(previous) < quietGap {
                // Same conversation, still going.
            } else {
                labels[item.id] = text(for: date, now: now, calendar: calendar)
            }
            previous = date
        }
        return labels
    }

    /// "Today 12:27 PM", "Yesterday 9:05 AM", "Monday 4:10 PM", "Oct 12, 4:10 PM", or with the
    /// year once it's another year's.
    static func text(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today \(time)") }
        if calendar.isDateInYesterday(date, relativeTo: now) { return String(localized: "Yesterday \(time)") }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
        if let days = days.day, days > 0, days < 7 {
            return date.formatted(.dateTime.weekday(.wide).hour().minute())
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }

    /// The time alone, for a message you point at.
    static func time(of date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

extension Calendar {
    fileprivate func isDateInYesterday(_ date: Date, relativeTo now: Date) -> Bool {
        guard let yesterday = self.date(byAdding: .day, value: -1, to: now) else { return false }
        return isDate(date, inSameDayAs: yesterday)
    }
}

/// A date between messages.
struct DateLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(size: 12, weight: .medium)
            .foregroundStyle(Theme.secondaryInk)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
