#if os(macOS)
    import AppKit
    import HermesKit
    import SwiftUI

    /// The screen, scaled to fit. While you're in control, the mouse and keyboard go to it: ⌘ acts
    /// as Control there, since the agent's desktop is Linux; ⌘Q and ⌘W stay with this app.
    struct ScreenCanvas: NSViewRepresentable {
        let screen: BotScreen
        let frame: CGImage
        @Binding var showsKeyboard: Bool

        func makeNSView(context: Context) -> CanvasView {
            let view = CanvasView()
            view.screen = screen
            return view
        }

        func updateNSView(_ view: CanvasView, context: Context) {
            view.screen = screen
            view.layer?.contents = frame
            view.frameSize = CGSize(width: frame.width, height: frame.height)
            view.controlling = screen.control == .you
        }
    }

    final class CanvasView: NSView {
        var screen: BotScreen?
        var frameSize = CGSize.zero
        var controlling = false {
            didSet {
                guard controlling != oldValue else { return }
                if controlling {
                    window?.makeFirstResponder(self)
                } else {
                    releaseEverything()
                }
                setAccessibilityHelp(
                    controlling
                        ? String(localized: "Your mouse and keyboard control the computer.")
                        : String(localized: "Take over to use the computer."))
            }
        }
        private var buttons: UInt8 = 0
        private var keysDown: [UInt16: UInt32] = [:]
        private var modifiers: NSEvent.ModifierFlags = []
        private var scrollCarry = CGSize.zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.contentsGravity = .resizeAspect
            layer?.magnificationFilter = .linear
            setAccessibilityElement(true)
            setAccessibilityRole(.image)
            setAccessibilityLabel(String(localized: "The agent's screen"))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { controlling }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
        }

        /// The event's spot in the screen's pixels, through the aspect-fit picture.
        private func screenPoint(_ event: NSEvent) -> CGPoint? {
            guard frameSize.width > 0, frameSize.height > 0 else { return nil }
            let point = convert(event.locationInWindow, from: nil)
            let scale = min(bounds.width / frameSize.width, bounds.height / frameSize.height)
            let drawn = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
            let origin = CGPoint(x: (bounds.width - drawn.width) / 2, y: (bounds.height - drawn.height) / 2)
            let x = (point.x - origin.x) / scale
            let y = (bounds.height - point.y - origin.y) / scale  // AppKit counts up from the bottom
            return CGPoint(x: min(max(x, 0), frameSize.width - 1), y: min(max(y, 0), frameSize.height - 1))
        }

        private func send(_ event: NSEvent, buttons next: UInt8) {
            buttons = next
            guard controlling, let point = screenPoint(event) else { return }
            screen?.pointer(x: point.x, y: point.y, buttons: buttons)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            send(event, buttons: buttons | 1)
        }
        override func mouseUp(with event: NSEvent) { send(event, buttons: buttons & ~1) }
        override func rightMouseDown(with event: NSEvent) { send(event, buttons: buttons | 4) }
        override func rightMouseUp(with event: NSEvent) { send(event, buttons: buttons & ~4) }
        override func otherMouseDown(with event: NSEvent) { send(event, buttons: buttons | 2) }
        override func otherMouseUp(with event: NSEvent) { send(event, buttons: buttons & ~2) }
        override func mouseMoved(with event: NSEvent) { send(event, buttons: buttons) }
        override func mouseDragged(with event: NSEvent) { send(event, buttons: buttons) }
        override func rightMouseDragged(with event: NSEvent) { send(event, buttons: buttons) }
        override func otherMouseDragged(with event: NSEvent) { send(event, buttons: buttons) }

        /// Wheel buttons 4 to 7 (masks 8, 16, 32, 64), one click per step; trackpads add up small deltas.
        override func scrollWheel(with event: NSEvent) {
            guard controlling, let point = screenPoint(event) else { return }
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 12 : 1
            scrollCarry.width += event.scrollingDeltaX
            scrollCarry.height += event.scrollingDeltaY
            while abs(scrollCarry.height) >= step {
                let mask: UInt8 = scrollCarry.height > 0 ? 8 : 16
                screen?.pointer(x: point.x, y: point.y, buttons: buttons | mask)
                screen?.pointer(x: point.x, y: point.y, buttons: buttons)
                scrollCarry.height -= scrollCarry.height > 0 ? step : -step
            }
            while abs(scrollCarry.width) >= step {
                let mask: UInt8 = scrollCarry.width > 0 ? 32 : 64
                screen?.pointer(x: point.x, y: point.y, buttons: buttons | mask)
                screen?.pointer(x: point.x, y: point.y, buttons: buttons)
                scrollCarry.width -= scrollCarry.width > 0 ? step : -step
            }
        }

        override func keyDown(with event: NSEvent) {
            guard controlling else { return super.keyDown(with: event) }
            guard let keysym = Self.keysym(for: event) else { return }
            keysDown[event.keyCode] = keysym.value
            screen?.key(keysym.value, down: true)
        }

        override func keyUp(with event: NSEvent) {
            guard controlling else { return super.keyUp(with: event) }
            guard let keysym = keysDown.removeValue(forKey: event.keyCode) else { return }
            screen?.key(keysym, down: false)
        }

        /// ⌘ shortcuts arrive here instead of `keyDown`, and their key-up never comes.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard controlling, window?.firstResponder === self,
                let key = event.charactersIgnoringModifiers?.lowercased(), key != "q", key != "w",
                let keysym = Self.keysym(for: event)
            else { return super.performKeyEquivalent(with: event) }
            screen?.key(keysym.value, down: true)
            screen?.key(keysym.value, down: false)
            return true
        }

        override func flagsChanged(with event: NSEvent) {
            guard controlling else { return super.flagsChanged(with: event) }
            let now = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            for (flag, keysym) in Self.modifierKeys {
                if now.contains(flag) != modifiers.contains(flag) {
                    screen?.key(keysym.value, down: now.contains(flag))
                }
            }
            modifiers = now
        }

        override func resignFirstResponder() -> Bool {
            releaseEverything()
            return super.resignFirstResponder()
        }

        /// Nothing stays held on the agent's screen once you leave it.
        private func releaseEverything() {
            for keysym in keysDown.values { screen?.key(keysym, down: false) }
            keysDown = [:]
            for (flag, keysym) in Self.modifierKeys where modifiers.contains(flag) {
                screen?.key(keysym.value, down: false)
            }
            modifiers = []
            buttons = 0
        }

        private static let modifierKeys: [(NSEvent.ModifierFlags, Keysym)] = [
            (.shift, .shift), (.control, .control), (.option, .alt), (.command, .control),
        ]

        /// Special keys by key code; otherwise the character the key types. With ⌘ or ⌃ held, the
        /// character without modifiers, so ⌘C reaches the desktop as Control-C.
        static func keysym(for event: NSEvent) -> Keysym? {
            let special: [UInt16: Keysym] = [
                36: .returnKey, 76: .returnKey, 48: .tab, 51: .backspace, 53: .escape, 117: .delete, 115: .home,
                119: .end, 116: .pageUp, 121: .pageDown, 123: .left, 124: .right, 125: .down, 126: .up,
                122: .function(1), 120: .function(2), 99: .function(3), 118: .function(4), 96: .function(5),
                97: .function(6), 98: .function(7), 100: .function(8), 101: .function(9), 109: .function(10),
                103: .function(11), 111: .function(12),
            ]
            if let key = special[event.keyCode] { return key }
            let plain = event.modifierFlags.isDisjoint(with: [.command, .control])
            let characters = plain ? event.characters : event.charactersIgnoringModifiers
            return characters?.first.flatMap(Keysym.init(character:))
        }
    }
#endif
