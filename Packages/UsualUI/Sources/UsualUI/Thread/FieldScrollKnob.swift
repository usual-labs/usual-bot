#if os(macOS)
    import AppKit
    import SwiftUI

    extension View {
        /// Mac: the app's thin knob on a text field that grows to a line limit and scrolls past it,
        /// so you can see there's more text above or below. Only while you type in the field: out
        /// of focus a field shows its first lines and doesn't scroll.
        func fieldScrollKnob() -> some View {
            modifier(FieldScrollKnob())
        }
    }

    private struct FieldScrollKnob: ViewModifier {
        @State private var scroll = FieldScroll()

        func body(content: Content) -> some View {
            content
                .background(FieldScrollAnchor(scroll: scroll).accessibilityHidden(true))
                .overlay { ScrollKnob(model: scroll.knob, idleOpacity: 0.16, scroll: scroll.scroll(to:)) { _ in } }
        }
    }

    /// Where a text field is scrolled to, read from AppKit: SwiftUI doesn't report it. A field has
    /// no scroll view. While you type in it, the window's field editor sits in a clip view over the
    /// field and scrolls there.
    @MainActor final class FieldScroll: NSObject {
        let knob = ScrollKnobModel()
        private weak var anchor: NSView?
        private weak var clip: NSClipView?
        private var responder: NSKeyValueObservation?

        /// `anchor` is a view behind the field, as large as it.
        func follow(_ anchor: NSView) {
            self.anchor = anchor
            responder = anchor.window?.observe(\.firstResponder) { [weak self] _, _ in
                // The editor is over the field only once focus has finished moving.
                Task { @MainActor in self?.update() }
            }
            update()
        }

        func update() {
            let editor = anchor?.window?.firstResponder as? NSTextView
            var clip = editor?.superview as? NSClipView
            // A window has one editor for all its fields. It's this field's while it's over the anchor.
            if let found = clip, let anchor,
                !found.convert(found.bounds, to: nil).intersects(anchor.convert(anchor.bounds, to: nil))
            {
                clip = nil
            }
            if clip !== self.clip {
                self.clip = clip
                // Unregistered again when this object goes.
                NotificationCenter.default.removeObserver(self)
                if let clip, let editor {
                    clip.postsBoundsChangedNotifications = true
                    clip.postsFrameChangedNotifications = true
                    editor.postsFrameChangedNotifications = true
                    for (name, view) in [
                        (NSView.boundsDidChangeNotification, clip), (NSView.frameDidChangeNotification, clip),
                        (NSView.frameDidChangeNotification, editor),
                    ] {
                        NotificationCenter.default.addObserver(
                            self, selector: #selector(viewChanged), name: name, object: view)
                    }
                }
            }
            var geometry = ScrollKnobGeometry()
            if let clip, let editor {
                geometry.contentHeight = editor.frame.height
                geometry.visibleHeight = clip.bounds.height
                geometry.offset = clip.bounds.minY
            }
            if knob.geometry != geometry { knob.geometry = geometry }
        }

        /// Scrolls to an offset from the top of the text.
        func scroll(to y: CGFloat) {
            guard let clip else { return }
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        }

        @objc private func viewChanged(_ notification: Notification) {
            update()
        }
    }

    struct FieldScrollAnchor: NSViewRepresentable {
        let scroll: FieldScroll

        func makeNSView(context: Context) -> AnchorView {
            let view = AnchorView()
            view.scroll = scroll
            return view
        }

        func updateNSView(_ view: AnchorView, context: Context) {}

        final class AnchorView: NSView {
            var scroll: FieldScroll?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                scroll?.follow(self)
            }

            // In case AppKit puts a new clip view over the resized field: nothing else would say so.
            override func setFrameSize(_ size: NSSize) {
                super.setFrameSize(size)
                scroll?.update()
            }

            /// Clicks are the field's.
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }
    }
#endif
