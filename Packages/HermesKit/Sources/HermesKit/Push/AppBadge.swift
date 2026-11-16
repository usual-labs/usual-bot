import Foundation

extension AppModel {
    /// The number on the app's icon: the unread replies the sidebar shows, less muted chats', which
    /// don't notify either. Only the gateway in use is counted; the other one's aren't loaded.
    /// Reads only the counts, not `sidebarContacts`, so a reply streaming in doesn't redo it.
    public var badgeCount: Int {
        let muted = push.muted
        return contacts.reduce(0) { total, contact in
            guard !muted.contains(contact.id) else { return total }
            return total + (threads[contact.id]?.unreadCount ?? rooms[contact.id]?.unreadCount ?? contact.unreadCount)
        }
    }

    /// Tells the notification extension what the app's icon now shows. The demo's count is made up.
    public func badgeShown(_ count: Int) {
        if !isDemo { AppBadge.save(count) }
    }
}

/// The badge the app last set, in the keychain group the notification extension shares
/// (`UsualPushKeychainGroup`), so each message pushed while the app is closed adds one to it. The
/// extension has no App Group, as for `GatewayNames`.
enum AppBadge {
    private static var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Usual Bot push relay",
            kSecAttrAccount as String: "badge",
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let group = Bundle.main.object(forInfoDictionaryKey: "UsualPushKeychainGroup") as? String,
            !group.isEmpty, !group.hasPrefix(".")
        {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    static func save(_ count: Int) {
        // Only builds with push have an extension to read it; tests and others leave the keychain alone.
        guard (Bundle.main.object(forInfoDictionaryKey: "UsualPushRelayURL") as? String)?.isEmpty == false else {
            return
        }
        let data = Data(String(count).utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
