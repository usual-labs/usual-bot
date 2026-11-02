import SwiftUI

extension View {
    /// Keeps `isLooking` on whether you're at this window, for what's meant for someone who isn't.
    func tracksLooking(_ isLooking: Binding<Bool>) -> some View {
        modifier(LooksAtWindow(isLooking: isLooking))
    }
}

private struct LooksAtWindow: ViewModifier {
    @Binding var isLooking: Bool
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
        @State private var screenIsAsleep = false
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase, initial: true) { update() }
            #if os(macOS)
                // A Mac window behind another app stays `.active`.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    update()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    isLooking = false
                }
                // Left in front and walked away from, a Mac mustn't silence your phone.
                .onReceive(workspaceEvents(NSWorkspace.screensDidSleepNotification)) { _ in
                    screenIsAsleep = true
                    update()
                }
                .onReceive(workspaceEvents(NSWorkspace.screensDidWakeNotification)) { _ in
                    screenIsAsleep = false
                    update()
                }
            #endif
    }

    private func update() {
        #if os(macOS)
            isLooking = scenePhase == .active && NSApp.isActive && !screenIsAsleep
        #else
            isLooking = scenePhase == .active
        #endif
    }

    #if os(macOS)
        private func workspaceEvents(_ name: Notification.Name) -> NotificationCenter.Publisher {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
        }
    #endif
}
