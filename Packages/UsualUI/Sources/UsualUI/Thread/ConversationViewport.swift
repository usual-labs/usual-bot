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
    private(set) var followsEnd = true
    private(set) var isScrollingByHand = false
    private(set) var viewport: ConversationViewport?
    /// The transcript load a search jumped into, which mustn't send the reader to the end.
    private var jumpedLoad: Int?

    mutating func update(_ viewport: ConversationViewport) -> CGFloat? {
        guard viewport.isUsable else { return nil }
        self.viewport = viewport
        return correction
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

    private var correction: CGFloat? {
        guard let viewport, !isScrollingByHand else { return nil }
        if followsEnd, abs(viewport.offset - viewport.end) > 1 { return viewport.end }
        if viewport.offset > viewport.end + 1 { return viewport.end }
        if viewport.offset < -1 { return 0 }
        return nil
    }
}
