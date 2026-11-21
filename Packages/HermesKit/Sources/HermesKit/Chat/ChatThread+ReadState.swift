import Foundation

/// A message to go back to, kept by when it was said and its words: a reloaded transcript numbers
/// its items afresh, and gives a message that arrived live the gateway's time instead.
struct ReturnPoint: Codable, Equatable, Sendable {
    var date: Date?
    var text: String

    init?(_ item: TranscriptItem) {
        guard let text = item.messageText else { return nil }
        self.date = item.date
        self.text = text
    }

    /// The item with these words said nearest this time.
    func find(in items: [TranscriptItem]) -> TranscriptItem.ID? {
        let when = date ?? .distantFuture
        return items.filter { $0.messageText == text }
            .min { abs(($0.date ?? when).timeIntervalSince(when)) < abs(($1.date ?? when).timeIntervalSince(when)) }?
            .id
    }
}

extension TranscriptItem {
    /// The words of a message you can go back to.
    fileprivate var messageText: String? {
        switch content {
        case .user(let text), .assistant(let text), .output(let text): text
        case .background(_, let result): result
        default: nil
        }
    }
}

extension ChatThread {
    /// When the newest message that counts as unread arrived: a reply or a background task's answer.
    var newestUnreadable: Date? {
        state.items.last { item in
            switch item.content {
            case .assistant, .background: return true
            default: return false
            }
        }?.date
    }

    /// Marked unread, here or on another device: shown unread, with no count unless replies came.
    public var isMarkedUnread: Bool { markedUnreadAt != nil }

    /// Mark as Unread. Stays until you open the chat again, even while it's on screen, and opening it
    /// goes back to `item` on this device. The app tells the gateway (`ReadSync.markUnread`).
    func markUnread(from item: TranscriptItem?) {
        markedUnreadAt = .now
        returnPoint = item.flatMap(ReturnPoint.init)
    }

    /// Mark as Read: nothing in the chat counts as unread any more, here or, through the gateway, on
    /// your other devices.
    func markRead() {
        markedUnreadAt = nil
        returnPoint = nil
        markViewed()
    }

    /// The chat was opened: a mark goes, and the message it was marked from, if it's still there,
    /// is where to show. Coming back to a window that already shows it isn't opening it.
    public func opened() -> TranscriptItem.ID? {
        let target = returnPoint?.find(in: state.items)
        returnPoint = nil
        guard isMarkedUnread else { return target }
        markedUnreadAt = nil
        if isVisible { markViewed() }
        return target
    }

    /// The gateway's read time is 0: marked unread on another device, or here by a write that got
    /// there. Leaves the count alone, as Hermes gives none.
    func adoptUnread() {
        unreadOnGateway = true
        if markedUnreadAt == nil { markedUnreadAt = .now }
    }

    /// The chat was read up to `date` (the gateway's time) on another device: what came before it
    /// stops counting as unread here, and a mark made before then goes. Never adds to the count.
    func adoptRead(at date: Date) {
        unreadOnGateway = false
        readOnGateway = max(readOnGateway ?? .distantPast, date)
        if let markedUnreadAt, date > markedUnreadAt {
            self.markedUnreadAt = nil
            returnPoint = nil
        }
        guard date > lastViewed ?? .distantPast else { return }
        lastViewed = date
        let newer = state.items.filter { item in
            switch item.content {
            case .assistant, .background, .routine: return (item.date ?? .distantPast) > date
            default: return false
            }
        }
        unreadCount = min(unreadCount, newer.count)
    }
}
