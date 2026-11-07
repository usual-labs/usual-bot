#if os(macOS)
    import SwiftUI

    /// Where a conversation is scrolled to, for its scroll knob. Kept in an object so a scroll
    /// redraws only the knob, not the conversation.
    @Observable final class ScrollKnobModel {
        var geometry = ScrollKnobGeometry()
    }

    /// The scroll view's own frame already stops at the bars pinned over the conversation, so
    /// its container is the part you see, and the knob's track is the whole frame.
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

    /// A thin, quiet knob at the conversation's trailing edge, as in Grok's Mac app. The system's
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
