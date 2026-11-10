#if os(macOS)
    import SwiftUI

    /// The glass behind the top of the chat and the sidebar, which scroll under it. macOS's soft
    /// scroll edge only fades, so this glass does the blurring: solid to the window's top edge,
    /// faded out below so the blur dissolves into what scrolls under it with no rim, line or
    /// shadow where the glass would end. The chat's reaches `fade` past its header; the sidebar's
    /// covers only the toolbar's band (its top safe area), so the list at rest isn't under it.
    struct HeaderGlass: View {
        /// The colour of what it sits on: the pane in a chat, the window in the sidebar.
        let ground: Color
        @Environment(\.appearsActive) private var appearsActive

        var body: some View {
            Group {
                if appearsActive {
                    // Tinted with the window's colour: plain glass reads as a pale haze in dark mode.
                    Color.clear.glassEffect(.regular.tint(Theme.window.opacity(0.4)), in: Rectangle())
                } else {
                    // macOS draws regular glass as a flat grey haze, without blur, in a window you
                    // aren't at: a grey band across the window's top. The ground's own colour
                    // fades what scrolls under the header instead.
                    ground
                }
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.45),
                        .init(color: .black.opacity(0.5), location: 0.75),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        /// How far the glass reaches past the bar it sits behind.
        static let fade: CGFloat = 24
    }
#endif
