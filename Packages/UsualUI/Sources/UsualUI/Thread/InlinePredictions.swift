#if os(macOS)
    import AppKit
    import SwiftUI

    extension View {
        /// Mac: the system's inline predictive text in this field, the grey completion you take
        /// with Tab, as WebKit gives a widget's input. A SwiftUI field leaves it off. It still
        /// follows Keyboard › Text Input › Show inline predictive text.
        func inlinePredictions() -> some View {
            background(PredictionAnchor().accessibilityHidden(true))
        }
    }

    private struct PredictionAnchor: NSViewRepresentable {
        func makeNSView(context: Context) -> AnchorView { AnchorView() }
        func updateNSView(_ view: AnchorView, context: Context) {}

        final class AnchorView: NSView {
            private var responder: NSKeyValueObservation?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                responder = window?.observe(\.firstResponder) { [weak self] _, _ in
                    // The editor is over the field only once focus has finished moving.
                    Task { @MainActor in self?.update() }
                }
            }

            /// A window has one editor for all its fields, so it's switched on only while it's
            /// editing the field over this view, and other fields keep their own setting.
            private func update() {
                let editor = window?.firstResponder as? NSTextView
                if let editor, editor.isFieldEditor, let field = editor.delegate as? NSTextField,
                    field.convert(field.bounds, to: nil).intersects(convert(bounds, to: nil))
                {
                    editor.inlinePredictionType = .yes
                    switched = editor
                } else if let switched {
                    switched.inlinePredictionType = .default
                    self.switched = nil
                }
            }

            private weak var switched: NSTextView?

            /// Clicks are the field's.
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }
    }
#endif
