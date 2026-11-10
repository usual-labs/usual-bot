import HermesKit
import SwiftUI

extension EnvironmentValues {
    /// The number that opens each chat with ⌘, for the sidebar to show while ⌘ is held (Mac).
    /// Empty the rest of the time.
    @Entry var chatShortcuts: [Contact.ID: Int] = [:]
}

/// "⌘3" on a chat in the sidebar, as a key cap. The Go menu says the same to VoiceOver.
struct ShortcutHint: View {
    let number: Int

    var body: some View {
        Text(verbatim: "⌘\(number)")
            .scaledFont(size: 11, weight: .medium)
            .foregroundStyle(Theme.secondaryInk)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

#if os(macOS)
    extension View {
        /// Keeps `isHeld` on whether ⌘ is held by itself in this window, to show what it opens.
        func tracksCommandHeld(_ isHeld: Binding<Bool>) -> some View {
            background(CommandHold(isHeld: isHeld).frame(width: 0, height: 0).accessibilityHidden(true))
        }
    }

    struct CommandHold: NSViewRepresentable {
        @Binding var isHeld: Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.view = view
            context.coordinator.isHeld = $isHeld
            context.coordinator.start()
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            context.coordinator.isHeld = $isHeld
        }

        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
            coordinator.stop()
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        @MainActor final class Coordinator {
            weak var view: NSView?
            var isHeld: Binding<Bool>?
            private var monitor: Any?
            private var observers: [any NSObjectProtocol] = []
            private var pending: Task<Void, Never>?

            /// Long enough that ⌘C and the like don't flash the numbers.
            private static let delay = Duration.milliseconds(250)

            func start() {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown]) {
                    [weak self] event in
                    MainActor.assumeIsolated { self?.saw(event) }
                    return event
                }
                // ⌘Tab and Spotlight take ⌘'s release with them.
                observers = [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification].map { name in
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.left() }
                    }
                }
            }

            func stop() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                pending?.cancel()
            }

            private func left() {
                if view?.window?.isKeyWindow != true || !NSApp.isActive { set(false) }
            }

            private func saw(_ event: NSEvent) {
                guard let window = view?.window, event.window === window else { return }
                guard Self.isCommandAlone(event.modifierFlags) else { return set(false) }
                switch event.type {
                case .flagsChanged: arm()
                // A shortcut pressed straight away needs no numbers. Once they show, they stay
                // while ⌘ does, to go from chat to chat.
                case .keyDown: pending?.cancel()
                default: break
                }
            }

            private func arm() {
                pending?.cancel()
                guard isHeld?.wrappedValue == false else { return }
                pending = Task { [weak self] in
                    try? await Task.sleep(for: Self.delay)
                    guard !Task.isCancelled, let self, view?.window?.isKeyWindow == true,
                        Self.isCommandAlone(NSEvent.modifierFlags)
                    else { return }
                    isHeld?.wrappedValue = true
                }
            }

            private func set(_ held: Bool) {
                pending?.cancel()
                if isHeld?.wrappedValue != held { isHeld?.wrappedValue = held }
            }

            /// ⌘ without ⇧, ⌥ or ⌃, which make other shortcuts. Caps Lock doesn't count.
            nonisolated static func isCommandAlone(_ flags: NSEvent.ModifierFlags) -> Bool {
                flags.intersection([.command, .shift, .option, .control]) == .command
            }
        }
    }
#endif
