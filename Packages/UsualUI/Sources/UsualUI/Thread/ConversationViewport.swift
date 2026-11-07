import Foundation

/// All dimensions come from the same layout pass; offsets count from the content's top.
struct ConversationViewport: Equatable {
    var contentHeight: CGFloat
    var height: CGFloat
    var offset: CGFloat

    var end: CGFloat { max(contentHeight - height, 0) }
    var isNearEnd: Bool { offset >= end - 40 }
    var isUsable: Bool {
        height > 0 && height.isFinite && contentHeight >= 0 && contentHeight.isFinite && offset.isFinite
    }
}

/// Scroll intent is separate from geometry: changing a row's height isn't a user's scroll.
struct ConversationScrollState {
    private(set) var followsEnd = true {
        didSet { if followsEnd { hasNewBelow = false } }
    }
    private(set) var isScrollingByHand = false
    private(set) var viewport: ConversationViewport?
    /// Something arrived at the end while the reader was away from it.
    private(set) var hasNewBelow = false
    /// The transcript load a search jumped into, which mustn't send the reader to the end.
    private var jumpedLoad: Int?
    private var arrivalLoad: Int?
    /// Your messages as last counted, to tell one you sent from a reload.
    private var lastSent: SentMessages?
    /// The content's height when earlier messages were added above it, until they're measured.
    private var heightBeforeAbove: CGFloat?
    /// Counts the times the space a conversation keeps at its end may go (`GrowsOnly`).
    private(set) var releases = 0
    /// That space is out of sight: you've scrolled more than its most above the end.
    private var spaceHidden = false

    /// Away from the newest message, so a button offers the way back.
    var isAwayFromEnd: Bool {
        guard !followsEnd, let viewport else { return false }
        return !viewport.isNearEnd
    }

    mutating func update(_ viewport: ConversationViewport) -> CGFloat? {
        guard viewport.isUsable else { return nil }
        self.viewport = viewport
        let hidden = !followsEnd && viewport.offset + viewport.height < viewport.contentHeight - GrowsOnly.limit
        if hidden, !spaceHidden { releases += 1 }
        spaceHidden = hidden
        if let before = heightBeforeAbove, viewport.contentHeight != before {
            heightBeforeAbove = nil
            // Even mid-gesture: what grew is above the reader, so this keeps them where they were.
            if !followsEnd { return viewport.offset + viewport.contentHeight - before }
        }
        return correction
    }

    /// Within a screen of the top, where earlier messages should be ready. Following the end,
    /// that's a conversation too short to fill two screens.
    var nearsTop: Bool {
        guard let viewport, heightBeforeAbove == nil else { return false }
        return (followsEnd ? viewport.end : viewport.offset) < viewport.height
    }

    /// Earlier messages are being added above what's shown.
    mutating func addingAbove() {
        heightBeforeAbove = viewport?.contentHeight
    }

    mutating func scrollingByHand(_ scrolling: Bool) -> CGFloat? {
        let wasScrolling = isScrollingByHand
        isScrollingByHand = scrolling
        if scrolling {
            followsEnd = false
        } else if wasScrolling {
            followsEnd = viewport?.isNearEnd ?? true
        }
        return correction
    }

    /// The transcript was loaded again. `load` counts the loads.
    mutating func reload(_ load: Int) -> CGFloat? {
        releases += 1
        guard load != jumpedLoad else { return nil }
        followsEnd = true
        return correction
    }

    /// Search showed a message further up: stay there, as after scrolling away by hand. A message
    /// found in history the gateway just sent arrives with that load (`atReload`), in either order.
    mutating func leaveEnd(atReload load: Int) {
        followsEnd = false
        jumpedLoad = load
    }

    /// A gesture's final phase can be lost when the app stops being active.
    mutating func resume() -> CGFloat? { scrollingByHand(false) }

    /// The conversation changed at its end. A change that came with a new load is history, not news.
    mutating func arrived(atReload load: Int) {
        defer { arrivalLoad = load }
        if !followsEnd, load == arrivalLoad { hasNewBelow = true }
    }

    /// The jump-to-latest button: back to the newest message, and follow it again.
    mutating func jumpToEnd() -> CGFloat? {
        followsEnd = true
        return correction
    }

    /// You sent a message: show it and what comes back, wherever you'd scrolled to. Another load
    /// holds other messages, so it says nothing about sending.
    mutating func sent(_ messages: SentMessages) -> CGFloat? {
        defer { lastSent = messages }
        guard let lastSent, lastSent.load == messages.load else { return nil }
        // An undo took your message back: what went with it was your doing.
        if messages.count < lastSent.count { releases += 1 }
        guard messages.count > lastSent.count else { return nil }
        followsEnd = true
        return correction
    }

    private var correction: CGFloat? {
        guard let viewport, !isScrollingByHand else { return nil }
        if followsEnd, abs(viewport.offset - viewport.end) > 1 { return viewport.end }
        if viewport.offset > viewport.end + 1 { return viewport.end }
        if viewport.offset < -1 { return 0 }
        return nil
    }
}

/// How many of the conversation's messages are yours, in which transcript load.
struct SentMessages: Equatable {
    var load = 0
    var count = 0
}
