import CryptoKit
import Foundation
import Security
import UserNotifications

/// Opens what the gateway sealed for this device, so the banner names the Bot and says what it
/// said. Usual's relay and Apple carry only the sealed text and a generic title, which is what
/// shows if this can't open it.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            return contentHandler(request.content)
        }
        if let sealed = content.userInfo["s"] as? String, let opened = Sealed.open(sealed) {
            content.title = opened.title
            content.subtitle = opened.subtitle ?? ""
            content.body = opened.body
            if let chat = opened.chat {
                // What the app reads to open the chat on a tap, and to clear it once you've seen it.
                // Each gateway has a `default`, so the thread names the gateway too (as
                // `NotificationThread` spells it).
                content.threadIdentifier = opened.gateway.map { "\($0)/\(chat)" } ?? chat
                content.userInfo["contact"] = chat
            }
            if let gateway = opened.gateway {
                content.userInfo["gateway"] = gateway
                // With two gateways, the banner says which one; the app keeps their names here.
                let names = GatewayNames.load()
                if names.count > 1, let name = names[gateway] {
                    content.subtitle = [name, content.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
                }
            }
            if opened.sound == false { content.sound = nil }
            // What a Bot says before its reply isn't unread on its own: the app counts the turn once.
            if opened.kind == "message", opened.interim != true, let count = Badge.added() {
                content.badge = NSNumber(value: count)
            }
            if let read = opened.read, !read.isEmpty {
                let threads = Set(read.map { chat in opened.gateway.map { "\($0)/\(chat)" } ?? chat })
                return TakeDown.read(threads, then: Finished(content: content, handler: contentHandler))
            }
        }
        contentHandler(content)
    }
}

/// Chats you read on another device since this one was last notified. The gateway's silent push
/// should already have taken their notifications down, but iOS rations those and drops them for an
/// app swiped away, so each notification carries them again and this extension finishes the job.
private enum TakeDown {
    static func read(_ threads: Set<String>, then finished: Finished) {
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            let ids = delivered.filter { threads.contains($0.request.content.threadIdentifier) }
                .map(\.request.identifier)
            if !ids.isEmpty { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids) }
            finished.handler(finished.content)
        }
    }
}

/// The new notification, held until the read ones are down. iOS calls back on its own queue, and
/// nothing else touches these meanwhile.
private struct Finished: @unchecked Sendable {
    let content: UNNotificationContent
    let handler: (UNNotificationContent) -> Void
}

/// What `Integrations/usual-bot` seals: JSON under AES-GCM, as nonce, then ciphertext and tag.
private struct Sealed: Decodable {
    let title: String
    let subtitle: String?
    let body: String
    let chat: String?
    let sound: Bool?
    /// `message`, `needs_you` or `test`.
    let kind: String?
    /// Which of this device's gateways sent it (plugin 0.5.0 and later).
    let gateway: String?
    /// Chats read on another device whose notifications should go first (plugin 0.9.0 and later).
    let read: [String]?
    /// What a Bot said on the way to its reply (plugin 0.12.0 and later).
    let interim: Bool?

    static func open(_ text: String) -> Sealed? {
        guard let key = sealKey(), let data = Data(base64Encoded: text),
            let box = try? AES.GCM.SealedBox(combined: data),
            let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key))
        else { return nil }
        return try? JSONDecoder().decode(Sealed.self, from: plain)
    }

    /// The key the app made when it signed up for push (`PushRelay`), in the keychain group both share.
    private static func sealKey() -> Data? {
        struct Registration: Decodable { let sealKey: Data }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "UsualPushKeychainGroup") as? String else {
            return nil
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Usual Bot push relay",
            kSecAttrAccount as String: "device",
            kSecAttrAccessGroup as String: group,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return (try? JSONDecoder().decode(Registration.self, from: data))?.sealKey
    }
}

/// Each gateway's name by its ID, as the app saves them (`GatewayNames` in HermesKit).
private enum GatewayNames {
    static func load() -> [String: String] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "UsualPushKeychainGroup") as? String else {
            return [:]
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Usual Bot push relay",
            kSecAttrAccount as String: "gateways",
            kSecAttrAccessGroup as String: group,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}

/// The number on the app's icon, as the app last set it (`AppBadge` in HermesKit). A message pushed
/// while the app is closed adds one; the app sets its own count again when it's next in front.
private enum Badge {
    /// Adds one and answers the new count, or `nil` without the app's count to add to.
    static func added() -> Int? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "UsualPushKeychainGroup") as? String else {
            return nil
        }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Usual Bot push relay",
            kSecAttrAccount as String: "badge",
            kSecAttrAccessGroup as String: group,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var result: CFTypeRef?
        var read = item
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
            let count = Int(String(decoding: data, as: UTF8.self))
        else { return nil }
        let next = count + 1
        let saved = SecItemUpdate(
            item as CFDictionary, [kSecValueData as String: Data(String(next).utf8)] as CFDictionary)
        return saved == errSecSuccess ? next : nil
    }
}
