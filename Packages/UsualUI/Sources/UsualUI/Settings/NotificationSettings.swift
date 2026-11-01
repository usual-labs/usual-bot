import SwiftUI
import UserNotifications

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct NotificationSettings: View {
    @AppStorage(AppPreferences.notificationsKey) private var enabled = true
    @AppStorage(AppPreferences.notificationSoundKey) private var sound = true
    @AppStorage(AppPreferences.notificationPreviewsKey) private var previews = true
    @State private var status: UNAuthorizationStatus?
    @State private var problem: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            Toggle("Background task completions", isOn: $enabled)
            Toggle("Play a sound", isOn: $sound).disabled(!enabled)
            Toggle("Show task and reply previews", isOn: $previews).disabled(!enabled)
        } header: {
            Text("Alerts")
        } footer: {
            Text(
                "Alerts appear when a background task finishes while Usual Bot isn’t in front. Hiding previews keeps task descriptions and reply text out of new notifications."
            )
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
                    "On iPhone, the connection closes when the app goes into the background. Alerts can arrive only while the app is still running; push notifications aren’t supported."
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
