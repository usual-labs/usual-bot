#if os(macOS)
    import AppKit
    import SwiftUI

    extension View {
        /// ⌘D in the message box: press it to dictate and again to stop, or hold it while you talk
        /// and let go to stop.
        func dictateKey(enabled: Bool, isListening: Bool, start: @escaping () -> Void, stop: @escaping () -> Void)
            -> some View
        {
            modifier(DictateKey(enabled: enabled, isListening: isListening, start: start, stop: stop))
        }
    }

    private struct DictateKey: ViewModifier {
        let enabled: Bool
        let isListening: Bool
        let start: () -> Void
        let stop: () -> Void
        /// When ⌘D started dictation, while the key is still down.
        @State private var pressedAt: Date?

        /// Held longer than this, letting go stops; a shorter press leaves dictation listening.
        static let hold: TimeInterval = 0.4

        func body(content: Content) -> some View {
            content.onKeyEvents([.keyDown, .keyUp], enabled: enabled) { event in
                guard event.charactersIgnoringModifiers?.lowercased() == "d" else { return false }
                if event.type == .keyUp {
                    guard let pressedAt else { return false }
                    self.pressedAt = nil
                    if Date.now.timeIntervalSince(pressedAt) >= Self.hold, isListening { stop() }
                    return true
                }
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
                    return false
                }
                if event.isARepeat { return true }
                if isListening {
                    pressedAt = nil
                    stop()
                } else {
                    pressedAt = .now
                    start()
                }
                return true
            }
        }
    }
#endif
