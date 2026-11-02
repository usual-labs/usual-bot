import HermesKit
import SwiftUI
import UserNotifications

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct NotificationSettings: View {
    let push: PushSettings
    let gatewayIsUnencrypted: Bool
    let isSignedIn: Bool

    @AppStorage(AppPreferences.messageNotificationsKey) private var messages = true
    @AppStorage(AppPreferences.needsYouNotificationsKey) private var needsYou = true
    @AppStorage(AppPreferences.notificationsKey) private var tasks = true
    @AppStorage(AppPreferences.notificationSoundKey) private var sound = true
    @AppStorage(AppPreferences.notificationPreviewsKey) private var previews = true
    @State private var status: UNAuthorizationStatus?
    @State private var problem: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            Toggle("Messages and replies", isOn: $messages)
            Toggle("When an agent needs you", isOn: $needsYou)
            Toggle("Background task completions", isOn: $tasks)
            Toggle("Play a sound", isOn: $sound).disabled(!anyEnabled)
            Toggle("Show previews", isOn: $previews).disabled(!anyEnabled)
        } header: {
            Text("Alerts")
        } footer: {
            Text(
                "Alerts appear when you’re not using Usual Bot. Hiding previews keeps what agents say and ask for out of new notifications."
            )
        }
        if isSignedIn {
            PushSection(
                push: push, gatewayIsUnencrypted: gatewayIsUnencrypted, messages: messages, needsYou: needsYou,
                previews: previews)
        }
        Section("System permission") {
            LabeledContent("Notifications", value: permissionLabel)
            if status == .notDetermined {
                Button("Allow Notifications") {
                    Task {
                        do {
                            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [
                                .alert, .sound,
                            ])
                        } catch {
                            problem = error.localizedDescription
                        }
                        await refresh()
                    }
                }
            } else {
                Button("Open Notification Settings", action: openSystemSettings)
            }
            if let problem { Text(problem).foregroundStyle(.red) }
        }
        #if os(iOS)
            Section {
                Text(
                    "Without push, iPhone alerts aren’t instant: the connection closes soon after you leave the app, and iOS decides when Usual Bot can check for new messages, which can take hours."
                )
                .foregroundStyle(.secondary)
            }
        #endif
        Section {
            Text("Your device’s notification settings and Focus can also silence alerts.")
                .foregroundStyle(.secondary)
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private var anyEnabled: Bool { messages || needsYou || tasks }

    private var permissionLabel: String {
        switch status {
        case .authorized, .provisional, .ephemeral: String(localized: "Allowed")
        case .denied: String(localized: "Off in system settings")
        case .notDetermined: String(localized: "Not requested")
        default: String(localized: "Checking…")
        }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openSystemSettings() {
        #if os(macOS)
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                NSWorkspace.shared.open(url)
            }
        #else
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        #endif
    }
}
