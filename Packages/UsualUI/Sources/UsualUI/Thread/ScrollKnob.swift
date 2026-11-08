import SwiftUI

extension View {
    /// The app's thin, quiet scroller on any scroll view in this view (a form, a list, a
    /// `ScrollView`), in place of the system's wide one. Nothing on iPhone, whose scroll
    /// indicators are already thin.
    func thinScroller() -> some View {
        #if os(macOS)
            modifier(ThinScroller())
        #else
            self
        #endif
    }
}

#if os(macOS)
    /// For a scroll view nothing else drives: its own position, for the knob to read and move.
    private struct ThinScroller: ViewModifier {
        @State private var position = ScrollPosition()

        func body(content: Content) -> some View {
            content.scrollPosition($position).scrollKnob($position)
        }
    }

    extension View {
        /// Our own thin knob in place of the system's scroller, on a scroll view that `position`
        /// drives: the conversation and the sidebar. `dragging` hears when a drag by hand starts
        /// and ends.
        func scrollKnob(
            _ position: Binding<ScrollPosition>, hidden: Bool = false, dragging: @escaping (Bool) -> Void = { _ in }
        ) -> some View {
            modifier(ScrollKnobModifier(position: position, hidden: hidden, dragging: dragging))
        }
    }

    private struct ScrollKnobModifier: ViewModifier {
        @Binding var position: ScrollPosition
        let hidden: Bool
        let dragging: (Bool) -> Void
        @State private var knob = ScrollKnobModel()

        func body(content: Content) -> some View {
            content
                // `.never`: `.hidden` still shows the system's scroller when a mouse is connected.
                .scrollIndicators(.never)
                .onScrollGeometryChange(for: ScrollKnobGeometry.self, of: ScrollKnobGeometry.init) {
                    knob.geometry = $1
                }
                .overlay {
                    if !hidden { ScrollKnob(model: knob, scroll: scroll(to:), dragging: dragging) }
                }
        }

        private func scroll(to y: CGFloat) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { position.scrollTo(y: y) }
        }
    }

    /// Where a scroll view is scrolled to, for its scroll knob. Kept in an object so a scroll
    /// redraws only the knob, not the content.
    @Observable final class ScrollKnobModel {
        var geometry = ScrollKnobGeometry()
    }

    /// The scroll view's own frame already stops at the bars pinned over it (the chat's bars, the
    /// sidebar's footer), so its container is the part you see, and the knob's track is the whole
    /// frame.
    struct ScrollKnobGeometry: Equatable {
        var contentHeight: CGFloat = 0
        var visibleHeight: CGFloat = 0
        /// From the top of the content, as `ScrollPosition.scrollTo(y:)` takes it.
        var offset: CGFloat = 0

        init() {}

        init(_ geometry: ScrollGeometry) {
            contentHeight = geometry.contentSize.height
            visibleHeight = geometry.containerSize.height
            offset = geometry.contentOffset.y + geometry.contentInsets.top
        }

        var maxOffset: CGFloat { max(contentHeight - visibleHeight, 0) }
    }

    /// A thin, quiet knob at a scroll view's trailing edge, as in Grok's Mac app. The system's
    /// scroller is the wide, bright one whenever a mouse is connected, and SwiftUI can't restyle
    /// it. Drag the knob to scroll; it widens under the pointer.
    struct ScrollKnob: View {
        let model: ScrollKnobModel
        /// Scrolls to an offset from the top of the content.
        let scroll: (CGFloat) -> Void
        /// A drag is a scroll by hand: the conversation stops following its end.
        let dragging: (Bool) -> Void

        @State private var hovering = false
        @State private var dragStart: CGFloat?

        private static let margin: CGFloat = 4
        private static let minLength: CGFloat = 36

        var body: some View {
            let g = model.geometry
            GeometryReader { proxy in
                if g.maxOffset > 1, g.visibleHeight > 0, g.contentHeight > 0 {
                    let track = max(proxy.size.height - Self.margin * 2, 0)
                    let length = min(max(track * g.visibleHeight / g.contentHeight, Self.minLength), track)
                    let travel = max(track - length, 1)
                    let progress = min(max(g.offset / g.maxOffset, 0), 1)
                    let active = hovering || dragStart != nil
                    Capsule()
                        .fill(Theme.ink.opacity(active ? 0.25 : 0.06))
                        .frame(width: active ? 8 : 5, height: length)
                        // A wider strip than it draws, so it's easy to grab.
                        .frame(width: 14, height: length)
                        .contentShape(Rectangle())
                        .onHover { hovering = $0 }
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { drag in
                                    if dragStart == nil {
                                        dragStart = progress
                                        dragging(true)
                                    }
                                    let to = min(max((dragStart ?? 0) + drag.translation.height / travel, 0), 1)
                                    scroll(to * g.maxOffset)
                                }
                                .onEnded { _ in
                                    dragStart = nil
                                    dragging(false)
                                }
                        )
                        .animation(.easeOut(duration: 0.15), value: active)
                        .offset(y: Self.margin + travel * progress)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 1)
                }
            }
            // VoiceOver scrolls the conversation itself.
            .accessibilityHidden(true)
        }
    }
#endif
