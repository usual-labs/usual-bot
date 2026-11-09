#if os(macOS)
    import AppKit
    import SwiftUI

    extension EnvironmentValues {
        /// Off while something over the chat, such as the search palette, takes typing instead.
        @Entry var messageBoxTakesTyping = true
    }

    extension View {
        /// Mac: typing in this window while nothing else takes text, after you clicked a Bot in the
        /// sidebar or the conversation, moves to the field, so you don't click it first.
        func typingFocuses(_ focused: FocusState<Bool>.Binding, enabled: Bool = true) -> some View {
            background(
                TypingFocus(focused: focused, enabled: enabled).frame(width: 0, height: 0).accessibilityHidden(true))
        }
    }

    struct TypingFocus: NSViewRepresentable {
        let focused: FocusState<Bool>.Binding
        let enabled: Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.view = view
            context.coordinator.focused = focused
            context.coordinator.enabled = enabled
            context.coordinator.start()
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            context.coordinator.focused = focused
            context.coordinator.enabled = enabled
        }

        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
            coordinator.stop()
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        @MainActor final class Coordinator {
            weak var view: NSView?
            var focused: FocusState<Bool>.Binding?
            var enabled = true
            private var monitor: Any?

            func start() {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let redirected = MainActor.assumeIsolated { self?.redirect(event) ?? false }
                    return redirected ? nil : event
                }
            }

            func stop() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }

            /// Keys held while focus moves, the first one included, to hand over in order.
            private var held: [NSEvent] = []

            /// Focuses the field and hands it the key once it has focus. The key is held back until
            /// then: sent now, it would go to the sidebar's type-to-select. Keys typed meanwhile wait
            /// behind it, so a fast "hi" doesn't arrive as "ih".
            private func redirect(_ event: NSEvent) -> Bool {
                guard enabled, let window = view?.window, event.window === window else { return false }
                if !held.isEmpty {
                    held.append(event)
                    return true
                }
                guard let focused, !focused.wrappedValue,
                    Self.types(event.characters ?? "", modifiers: event.modifierFlags),
                    !Self.takesKeys(window.firstResponder)
                else { return false }
                held = [event]
                focused.wrappedValue = true
                Task { @MainActor [weak self, weak window] in
                    // SwiftUI moves focus on a later pass. If it never lands, the keys go where
                    // they would have gone anyway.
                    for _ in 0..<20 {
                        if let editor = window?.firstResponder as? NSTextView, editor.isEditable {
                            // A field selects all its text as it takes focus; type on after it.
                            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                            break
                        }
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                    guard let self else { return }
                    let keys = held
                    held = []
                    for key in keys { window?.sendEvent(key) }
                }
                return true
            }

            /// Characters that start a message: no ⌘ or ⌃ shortcuts, arrows, Return, Tab, Escape or
            /// Space (which presses a focused button). ⌥ stays, since it types characters such as `@`
            /// on some layouts.
            nonisolated static func types(_ characters: String, modifiers: NSEvent.ModifierFlags) -> Bool {
                guard modifiers.isDisjoint(with: [.command, .control, .function]),
                    let scalar = characters.unicodeScalars.first
                else { return false }
                // Function keys arrive in the private-use range U+F700–U+F8FF.
                if (0xF700...0xF8FF).contains(scalar.value) { return false }
                return !CharacterSet.whitespacesAndNewlines.contains(scalar)
                    && !CharacterSet.controlCharacters.contains(scalar)
            }

            /// Something that takes typing itself: another text field, a web page, or the Bot's
            /// screen while you control it. A list or button doesn't, and gives typing up.
            static func takesKeys(_ responder: NSResponder?) -> Bool {
                if let text = responder as? NSTextView { return text.isEditable }
                if responder is CanvasView { return true }
                return responder is NSTextInputClient
            }
        }
    }
#endif
