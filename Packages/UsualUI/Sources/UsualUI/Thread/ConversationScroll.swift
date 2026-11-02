import SwiftUI

/// Open at the newest message, then follow it until the reader scrolls away. A `jump` from
/// search shows its message instead, highlighted for a moment.
struct ConversationScroll<Content: View>: View {
    var reload = 0
    var arrival: [Int] = []
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
                .padding(.horizontal, ThreadPane.composerMargin)
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
                if let pendingJump { show(pendingJump, with: proxy) }
            }
            .onScrollPhaseChange { _, phase in
                let byHand = phase == .tracking || phase == .interacting || phase == .decelerating
                move(to: scroll.scrollingByHand(byHand))
            }
            .onChange(of: reload) {
                settledReload = reload
                move(to: scroll.reload())
            }
            .onAppear { settledReload = reload }
            .onChange(of: jump, initial: true) { _, jump in
                guard let jump else { return }
                jumped()
                scroll.leaveEnd()
                highlighted = jump.itemID
                if scroll.viewport == nil { pendingJump = jump.itemID } else { show(jump.itemID, with: proxy) }
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if highlighted == jump.itemID { withAnimation(.easeOut(duration: 0.6)) { highlighted = nil } }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { move(to: scroll.resume()) }
            }
        }
    }

    private func show(_ itemID: Int, with proxy: ScrollViewProxy) {
        pendingJump = nil
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
