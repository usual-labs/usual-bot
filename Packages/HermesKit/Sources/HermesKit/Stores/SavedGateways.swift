import Foundation
import Security

/// A gateway this device is signed in to. There are at most `AppModel.gatewayLimit`, and one is
/// in use at a time; the others stay signed in but disconnected.
public struct SavedGateway: Codable, Identifiable, Equatable, Sendable {
    /// Made on this device and given to the gateway's push plugin, which seals it into each
    /// notification so this device can tell which gateway sent it. Never shown.
    public let id: String
    public let address: GatewayAddress
    /// The name you gave it on this device; without one it goes by its host.
    public var name: String?
    /// Whether this device hears from it. Off takes the device off the gateway's push list.
    public var notifies: Bool
    /// What was open when you left it, by setting (`AppModel.rememberedKeys`), for coming back.
    var remembered: [String: String]

    public init(id: String = UUID().uuidString, address: GatewayAddress, name: String? = nil, notifies: Bool = true) {
        self.id = id
        self.address = address
        self.name = name
        self.notifies = notifies
        remembered = [:]
    }

    public var displayName: String { name?.nonBlank ?? address.displayName }
}

/// The saved gateways, in UserDefaults. `gatewayAddress` still names the one in use, as it did
/// when the app knew only one, so an install from before keeps its sign-in and an older build
/// still finds it.
struct GatewayList {
    let defaults: UserDefaults
    /// Whether the notification extension hears the names; the demo's are made up.
    var keepsNames = true

    static let key = "gateways"
    static let activeKey = "gatewayAddress"

    func load() -> [SavedGateway] {
        if let data = defaults.data(forKey: Self.key),
            let saved = try? JSONDecoder().decode([SavedGateway].self, from: data)
        {
            return saved
        }
        // From before more than one: the one address becomes the first gateway, ID and all.
        guard let address = defaults.string(forKey: Self.activeKey).flatMap({ try? GatewayAddress(parsing: $0) })
        else { return [] }
        let first = [SavedGateway(address: address)]
        save(first)
        return first
    }

    func save(_ gateways: [SavedGateway]) {
        defaults.set(try? JSONEncoder().encode(gateways), forKey: Self.key)
        if keepsNames { GatewayNames.save(gateways) }
    }

    var activeAddress: GatewayAddress? {
        get { defaults.string(forKey: Self.activeKey).flatMap { try? GatewayAddress(parsing: $0) } }
        nonmutating set { defaults.set(newValue?.baseURL.absoluteString, forKey: Self.activeKey) }
    }
}

/// Each gateway's name by ID, in the keychain group the notification extension shares
/// (`UsualPushKeychainGroup`), so a banner can say which gateway it came from. The extension has
/// no App Group, and giving it one would need new provisioning profiles.
enum GatewayNames {
    private static var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Usual Bot push relay",
            kSecAttrAccount as String: "gateways",
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let group = Bundle.main.object(forInfoDictionaryKey: "UsualPushKeychainGroup") as? String,
            !group.isEmpty, !group.hasPrefix(".")
        {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    static func save(_ gateways: [SavedGateway]) {
        // Only builds with push have an extension to read it; tests and others leave the keychain alone.
        guard (Bundle.main.object(forInfoDictionaryKey: "UsualPushRelayURL") as? String)?.isEmpty == false else {
            return
        }
        guard !gateways.isEmpty,
            let data = try? JSONEncoder().encode(
                Dictionary(gateways.map { ($0.id, $0.displayName) }) { first, _ in first })
        else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

/// How a notification's thread is named, so a chat on one gateway never groups with, or clears,
/// the same chat on another. The notification extension spells it the same way.
public enum NotificationThread {
    public static func id(gateway: String?, chat: String) -> String {
        gateway.map { "\($0)/\(chat)" } ?? chat
    }
}
