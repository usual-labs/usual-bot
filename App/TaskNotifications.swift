import HermesKit
import UserNotifications

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Tells you when an agent's background task (`/bg`) finishes while Usual Bot isn't in front.
/// The first one asks for permission. On iPhone the app disconnects in the background, so only a
/// result that arrives while it's inactive but still open (say, under Control Center) notifies.
@MainActor
enum TaskNotifications {
    static func watch(_ model: AppModel) {
        model.backgroundTaskFinished = { contact, task, result in
            guard !isInFront else { return }
            Task { await post(agent: contact.name, task: task, result: result) }
        }
    }

    private static var isInFront: Bool {
        #if os(macOS)
            NSApp.isActive
        #else
            UIApplication.shared.applicationState == .active
        #endif
    }

    private static func post(agent: String, task: String, result: String) async {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        case .denied:
            return
        default:
            break
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(agent) finished a background task")
        content.subtitle = task
        content.body = plain(result)
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// The result without Markdown marks, short enough for a notification.
    private static func plain(_ markdown: String) -> String {
        let flat =
            (try? AttributedString(
                markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            .map { String($0.characters) } ?? markdown
        let line = flat.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > 240 ? String(line.prefix(239)) + "…" : line
    }
}
