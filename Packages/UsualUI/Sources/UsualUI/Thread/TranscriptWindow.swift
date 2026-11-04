import HermesKit

/// The part of a long conversation that's built. The transcript's stack isn't lazy (see the
/// known issues), so each message in it is measured on every layout: a chat of a few hundred
/// took most of a second to open and stuttered as the window resized. A conversation shows its
/// newest messages and adds earlier ones as you scroll up to them.
struct TranscriptWindow: Equatable {
    /// What a conversation opens with: enough to fill a tall window with short messages, few
    /// enough that switching chats stays quick. A short page fills up from the next ones.
    static let first = 12
    /// What scrolling up adds each time.
    static let page = 30
    /// The earliest item shown; `nil` shows the newest page.
    private(set) var firstID: Int?

    /// Where the shown items start. `including` keeps an item in view, such as one a search
    /// jumped to.
    func start(in items: [TranscriptItem], including target: Int? = nil) -> Int {
        let newest = max(items.count - Self.first, 0)
        var start = newest
        if let firstID {
            // Undo can remove the first item shown; the one after it takes its place.
            start = items.firstIndex { $0.id == firstID } ?? items.firstIndex { $0.id > firstID } ?? newest
        }
        if let target, let index = items.firstIndex(where: { $0.id == target }) { start = min(start, index) }
        return start
    }

    /// Back to the newest page, held there so messages arriving at the end don't push the top
    /// ones out from under the reader.
    mutating func reset(_ items: [TranscriptItem]) {
        firstID = items.isEmpty ? nil : items[max(items.count - Self.first, 0)].id
    }

    /// Adds a page of earlier items; `false` when there are none left to add.
    mutating func showEarlier(in items: [TranscriptItem], including target: Int? = nil) -> Bool {
        let start = start(in: items, including: target)
        guard start > 0 else { return false }
        firstID = items[max(start - Self.page, 0)].id
        return true
    }
}
