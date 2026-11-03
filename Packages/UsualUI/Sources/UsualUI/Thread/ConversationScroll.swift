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
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var settledReload = 0
    @State private var position = ScrollPosition()
    @State private var scroll = ConversationScrollState()
    /// Waiting for the first layout, which a jump into a chat just opened must follow.
    @State private var pendingJump: Int?
    @State private var highlighted: Int?
    /// A message just jumped to, shown again after the next layout: a move to the end that the
    /// same update queued (history arriving with the jump) lands after `scrollTo` and would win.
    @State private var jumpShown: Int?
    #if os(iOS)
        /// A message's words, shown to select part of.
        @State private var selecting: SelectingText?
    #endif

    var body: some View {
        // `ScrollPosition.scrollTo(id:anchor:)` ignores the anchor on iOS 18 and leaves the message
        // at the top, under the bar; the reader centres it on both platforms.
        ScrollViewReader { proxy in
            ScrollView {
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
                .frame(maxWidth: Theme.columnWidth)
                .padding(.horizontal, ThreadPane.contentMargin)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($position)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // No size-change anchor: only this policy moves the viewport as the content changes.
            .onScrollGeometryChange(for: ConversationViewport.self) { geometry in
                ConversationViewport(
                    contentHeight: geometry.contentSize.height, height: geometry.containerSize.height,
                    offset: geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, viewport in
                move(to: scroll.update(viewport))
                if let pendingJump {
                    show(pendingJump, with: proxy)
                } else if let shown = jumpShown {
                    jumpShown = nil
                    if !scroll.isScrollingByHand { scrollTo(shown, with: proxy) }
                }
            }
            .onScrollPhaseChange { _, phase in
                let byHand = phase == .tracking || phase == .interacting || phase == .decelerating
                move(to: scroll.scrollingByHand(byHand))
            }
            .onChange(of: reload) {
                settledReload = reload
                move(to: scroll.reload(reload))
                if let pendingJump { show(pendingJump, with: proxy) }
            }
            .onAppear { settledReload = reload }
            .onChange(of: jump, initial: true) { _, jump in
                guard let jump else { return }
                jumped()
                scroll.leaveEnd(atReload: reload)
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
                if phase == .active { move(to: scroll.resume()) }
            }
            .onChange(of: arrival, initial: true) { scroll.arrived(atReload: reload) }
            .onChange(of: sent, initial: true) { move(to: scroll.sent(sent)) }
            // Over the scroll view, so it sits above the message box and stays put as you scroll.
            .overlay(alignment: .bottom) {
                ZStack {
                    if scroll.isAwayFromEnd {
                        JumpToLatestButton(hasNew: scroll.hasNewBelow) { move(to: scroll.jumpToEnd()) }
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.18), value: scroll.isAwayFromEnd)
            }
            #if os(iOS)
                .environment(\.selectText) { selecting = SelectingText(text: $0) }
                .sheet(item: $selecting) { SelectTextSheet(text: $0.text) }
            #endif
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

/// Back to the newest message, shown while you're reading further up. A dot says more came in.
private struct JumpToLatestButton: View {
    let hasNew: Bool
    let action: () -> Void
    @Environment(\.chatContact) private var contact

    #if os(iOS)
        private static let size: CGFloat = 40
    #else
        private static let size: CGFloat = 36
    #endif

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: Self.size, height: Self.size)
                .floatingSurface(in: Circle())
                .overlay(alignment: .topTrailing) {
                    if hasNew {
                        Circle()
                            .fill(contact?.accent ?? Theme.primary)
                            .stroke(Theme.surface, lineWidth: 2)
                            .frame(width: 11, height: 11)
                            .offset(x: 1, y: -1)
                    }
                }
                // Reaches 44 pt on iPhone without a bigger circle.
                .padding(2)
                .contentShape(Circle())
        }
        .buttonStyle(.clickable)
        .help("Jump to latest message")
        .accessibilityLabel(Text("Jump to latest message"))
        .accessibilityValue(hasNew ? Text("New messages") : Text(""))
    }
}
