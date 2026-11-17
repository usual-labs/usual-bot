#if os(macOS)
    import AppKit
    import SwiftUI

    extension View {
        /// The pointing hand over this even where a message's text lies under it. The text view
        /// sets its I-beam all over itself, which beats SwiftUI's pointer style, so a button
        /// floating over the conversation needs this as well as `.clickable`.
        func handOverText() -> some View {
            background(HandOverText())
        }
    }

    private struct HandOverText: NSViewRepresentable {
        func makeNSView(context: Context) -> HandArea { HandArea() }
        func updateNSView(_ view: HandArea, context: Context) {}
    }

    /// Where the pointer is a hand, for the text views under it to leave alone.
    final class HandArea: NSView {
        /// Every one in a window. Weak: SwiftUI removes them as their buttons go.
        static let all = NSHashTable<HandArea>.weakObjects()
        private weak var leaving: NSWindow?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            leaving = window
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { Self.all.remove(self) } else { Self.all.add(self) }
            leaving?.resetCursorRects()
            window?.resetCursorRects()
            leaving = nil
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.resetCursorRects()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            window?.resetCursorRects()
        }

        /// Clicks go through to the button it's behind.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
#endif
