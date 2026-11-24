import Foundation

/// Where the NEW line goes in a chat or room on screen, as in Grok: above the first reply that was
/// unread when you opened it, or the message you marked it unread from. Kept by time or words, not
/// item ID, as a reloaded transcript numbers its items afresh.
public struct NewLine: Equatable, Sendable {
    enum Place: Equatable, Sendable {
        /// Replies after this time; `nil` when the chat has no read time, so the last `count` replies.
        case since(Date?, count: Int)
        /// The message Mark as Unread was chosen on.
        case at(ReturnPoint)
    }

    let place: Place

    /// The unread replies of a chat or room becoming visible; `nil` with none.
    static func unread(count: Int, since lastViewed: Date?) -> NewLine? {
        count > 0 ? NewLine(place: .since(lastViewed, count: count)) : nil
    }

    /// The item the line goes above, if it's still in `items`.
    public func itemID(in items: [TranscriptItem]) -> TranscriptItem.ID? {
        switch place {
        case .at(let point):
            return point.find(in: items)
        case .since(let date?, _):
            return items.first { $0.isNews && ($0.date ?? .distantPast) > date }?.id
        case .since(nil, let count):
            let news = items.filter(\.isNews)
            return news.count >= count ? news[news.count - count].id : news.first?.id
        }
    }
}

/// The NEW line of one chat or room. It's placed as the chat comes on screen with replies unread,
/// and stays while you're in it: a Mac window coming back to the front comes on screen again, but
/// only replies that arrived meanwhile move the line. Opening the chat again with none clears it.
struct NewLineKeeper {
    private(set) var line: NewLine?
    /// Placed since the chat was last opened.
    private var placed = false

    mutating func cameOnScreen(unread count: Int, since lastViewed: Date?) {
        let unread = NewLine.unread(count: count, since: lastViewed)
        placed = unread != nil
        if let unread { line = unread }
    }

    /// The chat was opened, before or after it came on screen: an older line goes, and Mark as
    /// Unread's message, if it's still there, takes the line.
    mutating func opened(at point: ReturnPoint? = nil) {
        if let point {
            line = NewLine(place: .at(point))
        } else if !placed {
            line = nil
        }
        placed = false
    }
}

extension TranscriptItem {
    /// What counts as unread: a Bot's reply, a background task's answer, a routine's result, or a
    /// room member's message.
    var isNews: Bool {
        switch content {
        case .assistant, .background, .routine, .member: true
        default: false
        }
    }
}
