import Foundation
import Testing

@testable import HermesKit
@testable import UsualUI

struct DateLabelTests {
    private let calendar = Calendar.current
    private var now: Date {
        // Mid-afternoon, so an hour either way stays on the same day.
        calendar.date(bySettingHour: 15, minute: 0, second: 0, of: .now) ?? .now
    }

    private func item(_ id: Int, _ date: Date?) -> TranscriptItem {
        var item = TranscriptItem(id: id, content: .assistant("\(id)"))
        item.date = date
        return item
    }

    @Test func aLabelStartsTheChatAndFollowsAQuietHourOrANewDay() {
        let yesterday = now.addingTimeInterval(-86_400)
        let items = [
            item(0, yesterday),
            item(1, yesterday.addingTimeInterval(5 * 60)),
            item(2, nil),
            item(3, now.addingTimeInterval(-2 * 3600)),
            item(4, now.addingTimeInterval(-2 * 3600 + 59 * 60)),
            item(5, now),
        ]
        let labels = DateLabels.labels(for: items, now: now, calendar: calendar)

        #expect(labels.keys.sorted() == [0, 3, 5])
        #expect(labels[0]?.hasPrefix("Yesterday") == true)
        #expect(labels[3]?.hasPrefix("Today") == true)
    }

    @Test func itemsWithoutDatesGetNoLabels() {
        let labels = DateLabels.labels(for: [item(0, nil), item(1, nil)], now: now, calendar: calendar)
        #expect(labels.isEmpty)
    }

    @Test func olderDatesNameTheDayOrTheDate() {
        let threeDaysAgo = now.addingTimeInterval(-3 * 86_400)
        #expect(
            DateLabels.text(for: threeDaysAgo, now: now, calendar: calendar)
                == threeDaysAgo.formatted(.dateTime.weekday(.wide).hour().minute()))
        let lastYear = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        #expect(
            DateLabels.text(for: lastYear, now: now, calendar: calendar).contains(lastYear.formatted(.dateTime.year())))
    }
}
