import Foundation

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

    /// The chat was read up to `date` (the gateway's time) on another device: what came before it
    /// stops counting as unread here. Never adds to the count.
    func adoptRead(at date: Date) {
        readOnGateway = max(readOnGateway ?? .distantPast, date)
        guard date > lastViewed ?? .distantPast else { return }
        lastViewed = date
        let newer = state.items.filter { item in
            switch item.content {
            case .assistant, .background: return (item.date ?? .distantPast) > date
            default: return false
            }
        }
        unreadCount = min(unreadCount, newer.count)
    }
}
