import HermesKit
import UserNotifications
import UsualUI
import os

/// Tells you what agents did while you weren't looking, and opens the chat when you tap it.
///
/// Once the gateway pushes to this device (`PushSettings`), messages and requests come that way,
/// sealed for this device and opened by the notification extension; these local alerts then cover
/// only what push doesn't, such as background task results. Without push, an iPhone hears only while
/// still connected or when iOS lets it check in (`BackgroundLink`).
@MainActor
final class AgentNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AgentNotifications()

    private nonisolated static let contactKey = "contact"
    /// Which of this device's gateways it's about (`SavedGateway.id`), as the push plugin seals it.
    private nonisolated static let gatewayKey = "gateway"
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
        model.alertsCleared = { [weak self] contact in
            guard let self else { return }
            let gateway = self.model?.activeGateway?.id
            Task { await self.clear(contact, on: gateway) }
        }
        model.push.currentChoices = {
            PushSettings.Choices(
                messages: Self.isWanted(.message), needsYou: Self.isWanted(.needsYou),
                previews: Self.isOn(AppPreferences.notificationPreviewsKey),
                sound: Self.isOn(AppPreferences.notificationSoundKey))
        }
        Task { await lookForNews() }
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
        // Another chat speaks up even while you're in the app; the one on screen never raises an alert.
        guard Self.isWanted(alert.kind), !Self.pushCovers(alert, model), model?.activeGateway?.notifies != false
        else { return }
        let gateway = model?.activeGateway?.id
        Task { await Self.post(alert, from: contact, on: gateway) }
    }

    /// The gateway pushes messages and requests to this device, so an alert here would say it twice.
    private static func pushCovers(_ alert: AgentAlert, _ model: AppModel?) -> Bool {
        [.message, .needsYou].contains(alert.kind) && model?.push.isActive == true
    }

    private static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool != false
    }

    private static func isWanted(_ kind: AgentAlert.Kind) -> Bool {
        let key =
            switch kind {
            case .message: AppPreferences.messageNotificationsKey
            case .needsYou: AppPreferences.needsYouNotificationsKey
            case .taskFinished, .goalEnded: AppPreferences.notificationsKey
            }
        return UserDefaults.standard.object(forKey: key) as? Bool != false
    }

    private static func post(_ alert: AgentAlert, from contact: Contact, on gateway: String?) async {
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
        case .goalEnded:
            content.title = String(localized: "\(contact.name)’s goal ended")
        }
        if defaults.object(forKey: AppPreferences.notificationPreviewsKey) as? Bool != false {
            content.subtitle = alert.subtitle ?? ""
            content.body = alert.preview.count > 240 ? String(alert.preview.prefix(239)) + "…" : alert.preview
        } else {
            content.body =
                switch alert.kind {
                case .message: String(localized: "New message. Open Usual Bot to read it.")
                case .needsYou: String(localized: "Open Usual Bot to answer.")
                case .taskFinished: String(localized: "Open Usual Bot to read the result.")
                case .goalEnded: String(localized: "Open Usual Bot to see how it ended.")
                }
        }
        if defaults.object(forKey: AppPreferences.notificationSoundKey) as? Bool != false {
            content.sound = .default
        }
        content.threadIdentifier = NotificationThread.id(gateway: gateway, chat: contact.id)
        content.userInfo = [contactKey: contact.id, gatewayKey: gateway].compactMapValues(\.self)
        do {
            try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
            log.notice("Notified about a \(String(describing: alert.kind), privacy: .public) alert")
        } catch {
            log.error("Couldn't notify: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Takes down what was said about a chat on `gateway` you've now seen, here or on another
    /// device (the gateway's silent push, `PushRegistration`), or all of that gateway's after
    /// signing out of it (`contact` is `nil`). The other gateway's stay.
    func clear(_ contact: Contact.ID?, on gateway: String?) async {
        let center = UNUserNotificationCenter.current()
        // An older plugin's notifications don't say which gateway sent them: with one gateway
        // they're its own, with two they can't be told apart, so they stay.
        let untagged = (model?.gateways.count ?? 0) <= 1
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { notification in
            let content = notification.request.content
            let from = content.userInfo[Self.gatewayKey] as? String
            guard from == gateway || (from == nil && untagged) else { return false }
            guard let contact else { return true }
            return content.threadIdentifier == NotificationThread.id(gateway: from, chat: contact)
        }
        .map(\.request.identifier)
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        await lookForNews()
    }

    /// Tells the model which gateways have notifications waiting, for the switcher's dot.
    func lookForNews() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        model?.showNews(on: Set(delivered.compactMap { $0.request.content.userInfo[Self.gatewayKey] as? String }))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// `heard` already decided a local alert should show. A push shows too, unless it's about the
    /// chat you're reading: the gateway may not have heard yet that it's open.
    ///
    /// Neither delegate method uses the `async` form: its thunk calls the completion handler from
    /// Swift's thread pool, and iOS aborts when a tapped notification's handler runs off the main
    /// thread (a `_performBlockAfterCATransactionCommitSynchronizes` assertion).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let gateway = content.userInfo[Self.gatewayKey] as? String
        guard content.userInfo["kind"] != nil, let chat = content.userInfo[Self.contactKey] as? String else {
            completionHandler([.banner, .list, .sound])
            Task { @MainActor in await lookForNews() }
            return
        }
        Task { @MainActor in
            let here = gateway == nil || gateway == model?.activeGateway?.id
            let reading = here && model?.isFocused == true && model?.visibleContactID == chat
            completionHandler(reading ? [] : [.banner, .list, .sound])
            // Delivered by now, or about to be: look again in a moment.
            try? await Task.sleep(for: .milliseconds(300))
            await lookForNews()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let contact = info[Self.contactKey] as? String
        let gateway = info[Self.gatewayKey] as? String
        Task { @MainActor in
            if let contact { open(contact, on: gateway) }
            completionHandler()
        }
    }

    /// Opens the chat, on its own gateway: switching to it if another is in use.
    private func open(_ contact: Contact.ID, on gateway: String?) {
        defer { showApp() }
        guard let model else { return }
        if let gateway {
            // Signed out of it since: there's no chat to open.
            guard model.gateways.contains(where: { $0.id == gateway }) else { return }
            if gateway != model.activeGateway?.id || !model.isSignedIn { model.switchTo(gateway) }
        } else if model.gateways.count > 1 {
            // An older plugin's: it could be either gateway's `default`, so the app just opens.
            return
        }
        model.requestedContactID = contact
    }
}
