#if os(macOS)
    import AppKit
    import SwiftUI

    /// Says when the pointer enters and leaves, using an AppKit tracking area instead of SwiftUI's
    /// `onHover`. For each message's `onHover`, SwiftUI hit-tests the text inside on every pointer
    /// move. In a long chat that kept the app busy for half a second at a time while the pointer
    /// crossed it. A tracking area only compares rectangles.
    struct PointerTracking: NSViewRepresentable {
        let changed: (Bool) -> Void

        func makeNSView(context: Context) -> TrackingView {
            let view = TrackingView()
            view.changed = changed
            return view
        }

        func updateNSView(_ view: TrackingView, context: Context) {
            view.changed = changed
        }

        final class TrackingView: NSView {
            var changed: (Bool) -> Void = { _ in }

            /// Clicks, selection and the menu go to the message on top.
            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                // `inVisibleRect` follows the view's size and scrolling, so one area is enough.
                if trackingAreas.isEmpty {
                    addTrackingArea(
                        NSTrackingArea(
                            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                            owner: self))
                }
            }

            override func mouseEntered(with event: NSEvent) { changed(true) }
            override func mouseExited(with event: NSEvent) { changed(false) }
        }
    }
#endif
