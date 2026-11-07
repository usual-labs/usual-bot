#if os(macOS)
    import SwiftUI

    extension View {
        /// A panel at the chat's trailing edge on the Mac, such as a Bot's profile or a room's
        /// details. It slides in from the window's edge, has its own close button, and you can
        /// drag its leading edge to resize it. Its width is kept under `widthKey`.
        func sidePanel(
            isPresented: Bool, widthKey: String, idealWidth: CGFloat, widthRange: ClosedRange<CGFloat>,
            closeTitle: LocalizedStringKey, close: @escaping () -> Void, @ViewBuilder panel: () -> some View
        ) -> some View {
            modifier(
                SidePanel(
                    isPresented: isPresented, width: AppStorage(wrappedValue: Double(idealWidth), widthKey),
                    widthRange: widthRange, closeTitle: closeTitle, close: close, panel: panel()))
        }
    }

    /// Not SwiftUI's `.inspector`. On the Mac that's an AppKit split view: it slides at an even
    /// speed on its own curve, lays the chat out again on every frame, and froze for up to 100 ms
    /// mid-slide. Here the chat is laid out once at its new width, and the panel slides on a curve
    /// that starts fast and settles.
    private struct SidePanel<Panel: View>: ViewModifier {
        let isPresented: Bool
        @AppStorage var width: Double
        let widthRange: ClosedRange<CGFloat>
        let closeTitle: LocalizedStringKey
        let close: () -> Void
        let panel: Panel

        @State private var dragStart: Double?

        /// An ease-out quartic: most of the way in the first few frames, then a long settle.
        /// Measured against Grok's Mac app, whose panel follows nearly the same path.
        static var motion: Animation { .timingCurve(0.25, 1, 0.5, 1, duration: 0.4) }

        func body(content: Content) -> some View {
            HStack(spacing: 0) {
                content
                if isPresented {
                    panel
                        .frame(width: shownWidth)
                        .frame(maxHeight: .infinity)
                        // Content wider than the panel mustn't spill over the chat; it still
                        // reaches up under the window's toolbar.
                        .mask { Rectangle().ignoresSafeArea(.container, edges: .top) }
                        .background { Theme.window.ignoresSafeArea() }
                        .overlay(alignment: .leading) { edge }
                        .overlay(alignment: .topTrailing) { closeButton }
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(Self.motion, value: isPresented)
            .preference(key: OpenPanelWidth.self, value: isPresented ? shownWidth : 0)
        }

        private var shownWidth: CGFloat {
            min(max(CGFloat(width), widthRange.lowerBound), widthRange.upperBound)
        }

        private var closeButton: some View {
            Button(action: close) { SidePanelIcon(systemName: "xmark") }
                .buttonStyle(.clickable)
                .help(Text(closeTitle))
                .accessibilityLabel(Text(closeTitle))
                .sidePanelTopRow()
        }

        /// The line between the chat and the panel, and a strip over it to drag.
        private var edge: some View {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .top)
                .overlay {
                    Rectangle()
                        .fill(Color.primary.opacity(0.001))
                        .frame(width: 8)
                        .pointerStyle(.frameResize(position: .leading))
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { drag in
                                    let start = dragStart ?? Double(shownWidth)
                                    dragStart = start
                                    width = min(
                                        max(start - drag.translation.width, Double(widthRange.lowerBound)),
                                        Double(widthRange.upperBound))
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                        .accessibilityHidden(true)
                }
        }
    }

    extension View {
        /// In a side panel's top row, level with the window buttons and the chat's round buttons:
        /// at the trailing edge, or just before the close button.
        func sidePanelTopRow(beforeClose: Bool = false) -> some View {
            padding(.top, 9)
                .padding(.trailing, beforeClose ? 8 + SidePanelIcon.size + 8 : 8)
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    /// A side panel's round button: an icon in glass, as the chat's Browser and Computer buttons.
    struct SidePanelIcon: View {
        static let size: CGFloat = 36
        let systemName: String

        var body: some View {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: Self.size, height: Self.size)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
        }
    }

    /// The open side panel's width; 0 with none open. The window keeps room for it, or the panel
    /// pushes the sidebar and the chat out of the window.
    struct OpenPanelWidth: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
#endif
