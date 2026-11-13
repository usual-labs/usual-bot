import HermesKit
import os

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Asks Apple for this install's push token and hands it to the relay. Only a build with a relay
/// address and the push entitlement asks; others would just be refused.
@MainActor
final class PushRegistration: NSObject {
    static var relay: PushRelay?

    static func start(_ relay: PushRelay) {
        self.relay = relay
        guard relay.isAvailable else { return }
        #if os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
        #else
            UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func received(_ token: Data) {
        guard let relay else { return }
        Task { await relay.received(token: token) }
    }

    static func failed(_ error: Error) {
        relay?.failedToRegister(error)
    }

    /// A silent push from the gateway: you read a chat on another device, so its notifications go.
    /// Answers whether it was one.
    static func received(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard let chat = PushRelay.chatReadElsewhere(in: userInfo) else { return false }
        await AgentNotifications.clear(chat)
        return true
    }
}

#if os(macOS)
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
            PushRegistration.received(token)
        }

        func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            PushRegistration.failed(error)
        }

        func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
            Task { _ = await PushRegistration.received(userInfo) }
        }
    }
#else
    final class AppDelegate: NSObject, UIApplicationDelegate {
        func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
            PushRegistration.received(token)
        }

        func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            PushRegistration.failed(error)
        }

        /// iOS wakes the app for this in the background (`remote-notification` in Info.plist), unless
        /// you swiped it away in the app switcher. Not the `async` form, as for notification taps
        /// (`AgentNotifications`).
        func application(
            _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
        ) {
            Task {
                completionHandler(await PushRegistration.received(userInfo) ? .newData : .noData)
            }
        }
    }
#endif
