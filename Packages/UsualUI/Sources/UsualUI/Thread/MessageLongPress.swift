import SwiftUI

extension EnvironmentValues {
    /// False inside an iPhone message, whose touch and hold opens the message's menu.
    @Entry var selectsTextInPlace = true
}

extension View {
    /// Words that select in place, except in an iPhone message: there touching and holding them
    /// would select a word instead of opening the message's menu, whose Select Text shows them in
    /// a sheet, as Messages, Signal and WhatsApp do.
    func messageTextSelection() -> some View { modifier(MessageTextSelection()) }
}

private struct MessageTextSelection: ViewModifier {
    @Environment(\.selectsTextInPlace) private var selectsInPlace

    func body(content: Content) -> some View {
        if selectsInPlace { content.textSelection(.enabled) } else { content }
    }
}

#if os(iOS)
    import UIKit

    /// Touch and hold on a message: `began` runs once the finger has stayed put for
    /// `minimumDuration`, while it's still down, so the haptic and the menu come then.
    /// A UIKit recognizer, because SwiftUI's `onLongPressGesture` here ran its action only once the
    /// finger lifted, so holding on showed nothing.
    struct MessageLongPress: UIGestureRecognizerRepresentable {
        var minimumDuration: TimeInterval = 0.4
        /// The finger is down on the message and may yet hold; false once it lifts, moves or holds.
        var pressing: (Bool) -> Void
        var began: () -> Void

        func makeUIGestureRecognizer(context: Context) -> Recognizer {
            let press = Recognizer()
            press.minimumPressDuration = minimumDuration
            press.pressing = pressing
            return press
        }

        func updateUIGestureRecognizer(_ recognizer: Recognizer, context: Context) {
            recognizer.minimumPressDuration = minimumDuration
            recognizer.pressing = pressing
        }

        func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
            if recognizer.state == .began {
                recognizer.pressing?(false)
                began()
            }
        }

        /// Says when a touch lands, which the action doesn't: a long press reports nothing until
        /// it begins or fails.
        final class Recognizer: UILongPressGestureRecognizer {
            var pressing: ((Bool) -> Void)?

            override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
                super.touchesBegan(touches, with: event)
                if state == .possible { pressing?(true) }
            }

            /// After it ends or fails: the finger lifted, moved off to scroll, or a swipe took it.
            override func reset() {
                super.reset()
                pressing?(false)
            }
        }
    }
#endif
