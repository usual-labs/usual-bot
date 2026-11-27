import SwiftUI

/// Open at the newest message, then follow it until the reader scrolls away; a button then offers
/// the way back. A `jump` from search shows its message instead, highlighted for a moment.
struct ConversationScroll<Content: View>: View {
    var reload = 0
    var arrival: [Int] = []
    /// Your messages: one more brings the end back into view.
    var sent = SentMessages()
    var jump: MessageJump? = nil
    /// Told the jump was taken, so it isn't taken again.
    var jumped: () -> Void = {}
    /// Adds earlier messages above as the reader nears the top; `false` when there are no more.
    var earlier: () -> Bool = { false }
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var settledReload = 0
    @State private var position = ScrollPosition()
    /// Out of SwiftUI's sight, as the offset in it changes on every frame of a scroll; `chrome` is
    /// the part that's drawn.
    @State private var tracker = ScrollTracker()
    @State private var chrome = ConversationChrome()
    /// Waiting for the first layout, which a jump into a chat just opened must follow.
    @State private var pendingJump: Int?
    @State private var highlighted: Int?
    /// A message just jumped to, shown again after the next layout: a move to the end that the
    /// same update queued (history arriving with the jump) lands after `scrollTo` and would win.
    @State private var jumpShown: Int?
    #if os(iOS)
        /// A message's words, shown to select part of.
        @State private var selecting: SelectingText?
        @State private var reveal = TimeReveal()
        @ScaledSize(relativeTo: .caption) private var revealWidth: CGFloat = 64
        @Environment(\.showConversationDetails) private var showDetails
    #endif

    var body: some View {
        // `ScrollPosition.scrollTo(id:anchor:)` ignores the anchor on iOS 18 and leaves the message
        // at the top, under the bar; the reader centres it on both platforms.
        TakesOfferedSize {
            scrollView
        }
    }

    private var scrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GrowsOnly(release: chrome.releases, end: arrival) {
                    // Lazy row-height estimates can leave a long transcript parked in blank space.
                    // Measure the loaded messages together so the scroll bounds are real at every offset.
                    VStack(alignment: .leading, spacing: 12) {
                        content
                    }
                    .environment(\.highlightedItem, highlighted)
                    .animation(
                        reduceMotion || reload != settledReload ? nil : .spring(duration: 0.32, bounce: 0.12),
                        value: arrival
                    )
                    .padding(.vertical, 16)
                    .zoomedFrame(maxWidth: Theme.columnWidth)
                    .padding(.horizontal, ThreadPane.contentMargin)
                    .frame(maxWidth: .infinity)
                    #if os(iOS)
                        .environment(reveal)
                        .modifier(RevealShift(reveal: reveal))
                    #endif
                }
            }
            #if os(iOS)
                .gesture(timesSwipe)
            #endif
            .scrollPosition($position)
            #if os(macOS)
                .scrollKnob($position) { byHand in apply { $0.scrollingByHand(byHand) } }
            #endif
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // No size-change anchor: only this policy moves the viewport as the content changes.
            .onScrollGeometryChange(for: ConversationViewport.self) { geometry in
                ConversationViewport(
                    contentHeight: geometry.contentSize.height, height: geometry.containerSize.height,
                    offset: geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, viewport in
                apply { $0.update(viewport) }
                if scroll.nearsTop { addEarlier() }
                if let pendingJump {
                    show(pendingJump, with: proxy)
                } else if let shown = jumpShown {
                    jumpShown = nil
                    if !scroll.isScrollingByHand { scrollTo(shown, with: proxy) }
                }
            }
            .onScrollPhaseChange { _, phase in
                let byHand = phase == .tracking || phase == .interacting || phase == .decelerating
                apply { $0.scrollingByHand(byHand) }
            }
            .onChange(of: reload) {
                settledReload = reload
                apply { $0.reload(reload) }
                if let pendingJump { show(pendingJump, with: proxy) }
            }
            .onAppear { settledReload = reload }
            .onDisappear { tracker.earlierSoon?.cancel() }
            .onChange(of: jump, initial: true) { _, jump in
                guard let jump else { return }
                jumped()
                apply {
                    $0.leaveEnd(atReload: reload)
                    return nil
                }
                highlighted = jump.itemID
                // A message in history just loaded waits for that load's layout.
                if scroll.viewport == nil || reload != settledReload {
                    pendingJump = jump.itemID
                } else {
                    show(jump.itemID, with: proxy)
                }
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if highlighted == jump.itemID { withAnimation(.easeOut(duration: 0.6)) { highlighted = nil } }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { apply { $0.resume() } }
            }
            .onChange(of: arrival, initial: true) {
                apply {
                    $0.arrived(atReload: reload)
                    return nil
                }
            }
            .onChange(of: sent, initial: true) { apply { $0.sent(sent) } }
            // Over the scroll view, so it sits above the message box and stays put as you scroll.
            .overlay(alignment: .bottom) {
                ZStack {
                    if chrome.isAwayFromEnd {
                        JumpToLatestButton(hasNew: chrome.hasNewBelow) { apply { $0.jumpToEnd() } }
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.18), value: chrome.isAwayFromEnd)
            }
            #if os(iOS)
                .environment(\.selectText) { selecting = SelectingText(text: $0, quote: $1) }
                .sheet(item: $selecting) { SelectTextSheet(text: $0.text, quote: $0.quote) }
            #endif
        }
    }

    #if os(iOS)
        /// Pulled left, the conversation shows when each message was sent; flicked left, it opens
        /// the Bot's page or the room's details, as in Grok's app.
        private var timesSwipe: SidewaysPan {
            SidewaysPan(direction: .left) { x in
                reveal.width = revealWidth
                reveal.offset = resisted(-x, limit: revealWidth)
            } ended: { x, velocity in
                if velocity < -700, x < -24 { showDetails?() }
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.15)) {
                    reveal.offset = 0
                }
            }
        }
    #endif

    private var scroll: ConversationScrollState { tracker.state }

    /// Changes the scroll state, redraws only when what's drawn changed, and makes the correction
    /// the change asks for.
    private func apply(_ change: (inout ConversationScrollState) -> CGFloat?) {
        let offset = change(&tracker.state)
        if tracker.state.chrome != chrome { chrome = tracker.state.chrome }
        move(to: offset)
    }

    /// Adds a page of earlier messages. One the screen doesn't need yet comes a moment after the chat
    /// is drawn: building it first held every chat switch for as long again, and a chat left before
    /// then never builds it.
    private func addEarlier() {
        guard scroll.earlierCanWait else {
            tracker.earlierSoon?.cancel()
            tracker.earlierSoon = nil
            if earlier() { tracker.state.addingAbove() }
            return
        }
        guard tracker.earlierSoon == nil else { return }
        tracker.earlierSoon = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            tracker.earlierSoon = nil
            if scroll.nearsTop, earlier() { tracker.state.addingAbove() }
        }
    }

    private func show(_ itemID: Int, with proxy: ScrollViewProxy) {
        pendingJump = nil
        jumpShown = itemID
        scrollTo(itemID, with: proxy)
    }

    private func scrollTo(_ itemID: Int, with proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { proxy.scrollTo(itemID, anchor: .center) }
    }

    private func move(to offset: CGFloat?) {
        guard let offset else { return }
        // Correcting layout must not become another scroll animation or inherit a row transition.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { position.scrollTo(y: offset) }
    }
}

/// Holds a conversation's scroll state where SwiftUI doesn't watch it.
@MainActor private final class ScrollTracker {
    var state = ConversationScrollState()
    /// Earlier messages to add once the chat has been drawn (`addEarlier`).
    var earlierSoon: Task<Void, Never>?
}

/// A conversation never gets shorter at its end: what leaves it, such as a card you answered,
/// leaves its space behind, and what arrives next fills that space first. Following the newest
/// message, the chat then only ever moves up. Only a change at the end (`end`, the conversation's
/// `arrival`) starts keeping space: something shrinking above it, as an image loads or the
/// transcript reloads shorter while a chat opens, would otherwise open the chat over a blank. The
/// space goes when `release` changes, which happens while it's out of sight, and when the width
/// changes. It's at most `limit` tall: removing more than that, as an undo can, is something you
/// did, and the chat may move for it.
struct GrowsOnly: Layout {
    var release: Int
    var end: [Int]
    static let limit: CGFloat = 320

    struct Cache {
        var width: CGFloat?
        var release: Int?
        var end: [Int]?
        var floor: CGFloat = 0
        /// The content's own height in the last measure, to tell whether space is being kept.
        var natural: CGFloat = 0
        var keeping = false
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }
    // The default makes a new cache, which would forget the floor whenever a message arrives.
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(proposal)
        cache.natural = size.height
        guard proposal.width != nil, proposal.width == cache.width, cache.release == release,
            cache.keeping || cache.end != end
        else { return size }
        return CGSize(width: size.width, height: max(size.height, min(cache.floor, size.height + Self.limit)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, proposal: proposal)
        cache.keeping = cache.width == bounds.width && cache.release == release && bounds.height > cache.natural + 0.5
        cache.width = bounds.width
        cache.release = release
        cache.end = end
        cache.floor = bounds.height
    }
}

/// Fills the space it's offered without measuring the conversation. A scroll view asked its size
/// measures every message inside it, and the bars pinned over a chat (`safeAreaBar`) and the
/// window's minimum size ask on every update: that was about a fifth of switching chats.
struct TakesOfferedSize: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width, let height = proposal.height else {
            return subviews.first?.sizeThatFits(proposal) ?? .zero  // an ideal size: only the content knows
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }

    /// None. Left to the default, a stack around it (the kept chats' `ZStack`) asking for its
    /// alignment placed the scroll view, which measured every message in it: each chat kept out of
    /// sight made opening another one slower.
    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? { nil }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? { nil }
}

/// Back to the newest message, shown while you're reading further up. A dot says more came in.
/// iPhone: a glass circle. Mac: a thin arrow on a solid circle, as in Grok's app; glass drew it
/// there as a small pale disc that got lost in the text under it.
private struct JumpToLatestButton: View {
    let hasNew: Bool
    let action: () -> Void
    @Environment(\.chatContact) private var contact

    var body: some View {
        button
            .overlay(alignment: .topTrailing) {
                if hasNew {
                    Circle()
                        .fill(contact?.accent ?? Theme.primary)
                        .zoomedFrame(width: 11, height: 11)
                        .offset(x: 1, y: -1)
                        .allowsHitTesting(false)
                }
            }
            .help("Jump to latest message")
            .accessibilityLabel(Text("Jump to latest message"))
            .accessibilityValue(hasNew ? Text("New messages") : Text(""))
    }

    @ViewBuilder private var button: some View {
        #if os(iOS)
            Button("Jump to latest message", systemImage: "arrow.down", action: action)
                .labelStyle(.iconOnly)
                .zoomedFont(size: 15, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .buttonStyle(.clickable(.glass))
                .buttonBorderShape(.circle)
                .controlSize(.large)
        #else
            Button(action: action) {
                Image(systemName: "arrow.down")
                    .zoomedFont(size: 14, weight: .regular)
                    .foregroundStyle(Theme.ink)
                    .zoomedFrame(width: 32, height: 32)
                    .background(Theme.bubble, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.clickable)
            .handOverText()
        #endif
    }
}
