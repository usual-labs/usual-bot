import SwiftUI

/// Open at the newest message, then follow it until the reader scrolls away.
struct ConversationScroll<Content: View>: View {
    var reload = 0
    var arrival: [Int] = []
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var settledReload = 0
    @State private var position = ScrollPosition()
    @State private var scroll = ConversationScrollState()

    var body: some View {
        ScrollView {
            // Lazy row-height estimates can leave a long transcript parked in blank space.
            // Measure the loaded messages together so the scroll bounds are real at every offset.
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .animation(
                reduceMotion || reload != settledReload ? nil : .spring(duration: 0.32, bounce: 0.12), value: arrival
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
        }
        .onScrollPhaseChange { _, phase in
            move(to: scroll.scrollingByHand(phase == .tracking || phase == .interacting || phase == .decelerating))
        }
        .onChange(of: reload) {
            settledReload = reload
            move(to: scroll.reload())
        }
        .onAppear { settledReload = reload }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { move(to: scroll.resume()) }
        }
    }

    private func move(to offset: CGFloat?) {
        guard let offset else { return }
        // Correcting layout must not become another scroll animation or inherit a row transition.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { position.scrollTo(y: offset) }
    }
}
