#if os(iOS)
    import SwiftUI

    /// iPhone: the pane's colour behind a chat's bars, fading out towards the conversation, as in
    /// Grok's phone app. The soft scroll edge alone left text sharp under the status bar and the
    /// home indicator. Solid at the screen's edge, so the clock and the bars stay readable.
    struct EdgeScrim: View {
        let edge: VerticalEdge

        var body: some View {
            LinearGradient(
                stops: [
                    .init(color: Theme.pane, location: 0),
                    .init(color: Theme.pane.opacity(0.85), location: 0.4),
                    // The pane's own colour gone clear: plain `.clear` greys the middle in light mode.
                    .init(color: Theme.pane.opacity(0), location: 1),
                ],
                startPoint: edge == .top ? .top : .bottom,
                endPoint: edge == .top ? .bottom : .top
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    extension View {
        /// Over the conversation, under the navigation bar: the scrim fills the top safe area (the
        /// status bar and the bar with the name), ending where the conversation starts, so it stays
        /// off the call bar below.
        func topEdgeScrim() -> some View {
            overlay {
                GeometryReader { proxy in
                    EdgeScrim(edge: .top).frame(height: proxy.safeAreaInsets.top)
                }
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
            }
        }

        /// Behind the message box's bar, down past the home indicator. It starts at the bar's top
        /// rather than above it, so it stays off Jump to latest just above the box.
        func bottomEdgeScrim() -> some View {
            background {
                EdgeScrim(edge: .bottom).ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }
#endif
