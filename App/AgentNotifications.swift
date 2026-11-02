import HermesKit
import UserNotifications
import UsualUI
import os

/// Tells you what agents did while you weren't looking, and opens the chat when you tap it.
///
/// On iPhone the app disconnects in the background, so these fire only while it's still connected
/// or when iOS lets it check in (`BackgroundLink`). Instant alerts there come from the gateway
/// through ntfy or Pushover (`PushSettings`).
@MainActor
final class AgentNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AgentNotifications()

    private nonisolated static let contactKey = "contact"
    private static let log = Logger(subsystem: "UsualBot", category: "notifications")
    private var model: AppModel?
    private var showApp: () -> Void = {}

    func watch(_ model: AppModel, showApp: @escaping () -> Void) {
        self.model = model
        self.showApp = showApp
        // Set before launch ends, or a tap that launched the app is lost.
        UNUserNotificationCenter.current().delegate = self
        model.agentAlerted = { [weak self] contact, alert in self?.heard(alert, from: contact) }
        model.alertWithdrawn = { id in
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }
        model.alertsCleared = { contact in Task { await Self.clear(contact) } }
    }

    func askForPermission() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // An ad-hoc signed Mac build lands here: macOS doesn't let those notify.
            Self.log.error("Couldn't ask to notify: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func heard(_ alert: AgentAlert, from contact: Contact) {
        guard Self.isWanted(alert.kind), model?.isFocused != true, !Self.pushCovers(alert, model) else { return }
        Task { await Self.post(alert, from: contact) }
    }

    /// An iPhone would hear it twice: ntfy or Pushover is installed right beside this app. A Mac
    /// usually has neither, and it's this app that's there all day.
    private static func pushCovers(_ alert: AgentAlert, _ model: AppModel?) -> Bool {
        #if os(iOS)
            alert.kind != .taskFinished && model?.push.isActive == true
        #else
            false
        #endif
    }

    private static func isWanted(_ kind: AgentAlert.Kind) -> Bool {
        let key =
            switch kind {
            case .message: AppPreferences.messageNotificationsKey
            case .needsYou: AppPreferences.needsYouNotificationsKey
            case .taskFinished: AppPreferences.notificationsKey
            }
        return UserDefaults.standard.object(forKey: key) as? Bool != false
    }

    private static func post(_ alert: AgentAlert, from contact: Contact) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus != .denied else { return }
        let defaults = UserDefaults.standard
        let content = UNMutableNotificationContent()
        switch alert.kind {
        case .message:
            content.title = contact.name
        case .needsYou:
            content.title = String(localized: "\(contact.name) needs you")
        case .taskFinished:
            content.title = String(localized: "\(contact.name) finished a background task")
        }
        if defaults.object(forKey: AppPreferences.notificationPreviewsKey) as? Bool != false {
            content.subtitle = alert.subtitle ?? ""
            content.body = plain(alert.preview)
        } else {
            content.body =
                switch alert.kind {
                case .message: String(localized: "New message. Open Usual Bot to read it.")
                case .needsYou: String(localized: "Open Usual Bot to answer.")
                case .taskFinished: String(localized: "Open Usual Bot to read the result.")
                }
        }
        if defaults.object(forKey: AppPreferences.notificationSoundKey) as? Bool != false {
            content.sound = .default
        }
        content.threadIdentifier = contact.id
        content.userInfo = [contactKey: contact.id]
        do {
            try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
            log.notice("Notified about a \(String(describing: alert.kind), privacy: .public) alert")
        } catch {
            log.error("Couldn't notify: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Takes down what was said about a chat you've now seen, or everything after signing out.
    private static func clear(_ contact: Contact.ID?) async {
        let center = UNUserNotificationCenter.current()
        guard let contact else {
            center.removeAllDeliveredNotifications()
            return
        }
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { $0.request.content.threadIdentifier == contact }.map(\.request.identifier)
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }

    /// The text without Markdown marks, short enough for a notification.
    private static func plain(_ markdown: String) -> String {
        let flat =
            (try? AttributedString(
                markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            .map { String($0.characters) } ?? markdown
        let line = flat.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > 240 ? String(line.prefix(239)) + "…" : line
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// `heard` already decided this one should show, so show it even with the app in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let contact = response.notification.request.content.userInfo[Self.contactKey] as? String else { return }
        await MainActor.run { open(contact) }
    }

    private func open(_ contact: Contact.ID) {
        model?.requestedContactID = contact
        showApp()
    }
}
