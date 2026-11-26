#if os(macOS)
    import AppKit
    import HermesKit

    /// Logs the Mac sleeping, waking and locking, to line up with the gateway link (`Trace`): a socket
    /// that slept is only found dead by its heartbeat, up to 45 s after waking.
    enum PowerTrace {
        static func start() {
            let workspace = NSWorkspace.shared.notificationCenter
            let names: [(Notification.Name, String)] = [
                (NSWorkspace.willSleepNotification, "mac.sleep"),
                (NSWorkspace.didWakeNotification, "mac.wake"),
                (NSWorkspace.screensDidSleepNotification, "mac.screen_sleep"),
                (NSWorkspace.screensDidWakeNotification, "mac.screen_wake"),
                (NSWorkspace.sessionDidResignActiveNotification, "mac.session_away"),
                (NSWorkspace.sessionDidBecomeActiveNotification, "mac.session_back"),
            ]
            for (name, event) in names {
                workspace.addObserver(forName: name, object: nil, queue: .main) { _ in Trace.event(event) }
            }
            let distributed = DistributedNotificationCenter.default()
            for (name, event) in [
                ("com.apple.screenIsLocked", "mac.locked"), ("com.apple.screenIsUnlocked", "mac.unlocked"),
            ] {
                distributed.addObserver(forName: .init(name), object: nil, queue: .main) { _ in Trace.event(event) }
            }
        }
    }
#endif
