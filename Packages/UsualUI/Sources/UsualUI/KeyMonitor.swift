#if os(macOS)
    import AppKit
    import SwiftUI

    extension View {
        /// Mac: sees this window's key events before anything else does, for keys a menu item
        /// can't take, such as a key let go. `handle` returns `true` to keep the event from going on.
        func onKeyEvents(
            _ mask: NSEvent.EventTypeMask, enabled: Bool = true, handle: @escaping (NSEvent) -> Bool
        ) -> some View {
            background(
                KeyMonitor(mask: mask, enabled: enabled, handle: handle)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true))
        }

        /// ⌘= zooms in as ⌘+ does: + shares the = key on most keyboards, where ⌘+ needs Shift too.
        func zoomKeys(_ zoom: Binding<Int>) -> some View {
            onKeyEvents(.keyDown) { event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                    event.charactersIgnoringModifiers == "="
                else { return false }
                zoom.wrappedValue = Zoom.zoomedIn(zoom.wrappedValue)
                return true
            }
        }
    }

    private struct KeyMonitor: NSViewRepresentable {
        let mask: NSEvent.EventTypeMask
        let enabled: Bool
        let handle: (NSEvent) -> Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.view = view
            update(context.coordinator)
            context.coordinator.start(mask)
            return view
        }

        func updateNSView(_ view: NSView, context: Context) { update(context.coordinator) }

        private func update(_ coordinator: Coordinator) {
            coordinator.enabled = enabled
            coordinator.handle = handle
        }

        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

        func makeCoordinator() -> Coordinator { Coordinator() }

        @MainActor final class Coordinator {
            weak var view: NSView?
            var enabled = true
            var handle: (NSEvent) -> Bool = { _ in false }
            private var monitor: Any?

            func start(_ mask: NSEvent.EventTypeMask) {
                monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                    let handled = MainActor.assumeIsolated { self?.handles(event) ?? false }
                    return handled ? nil : event
                }
            }

            func stop() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }

            private func handles(_ event: NSEvent) -> Bool {
                guard enabled, let window = view?.window, event.window === window else { return false }
                return handle(event)
            }
        }
    }
#endif
