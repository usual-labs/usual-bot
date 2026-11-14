import Foundation
import Security

/// Where a gateway's tokens are kept between launches.
public protocol TokenStore: Sendable {
    func load(for gateway: GatewayAddress) throws -> TokenSet?
    func save(_ tokens: TokenSet, for gateway: GatewayAddress) throws
    func delete(for gateway: GatewayAddress) throws
    /// Taken around every renewal when another process (the share extension) can renew the same
    /// sign-in; `nil` when only this one can.
    var refreshLock: RefreshLock? { get }
}

extension TokenStore {
    public var refreshLock: RefreshLock? { nil }
}

/// Stores tokens as a generic password in the Keychain, one item per gateway, readable only
/// after the device has been unlocked once and never synced or backed up to another device.
///
/// On iPhone the item sits in the App Group's access group, so the share extension can send with
/// the same sign-in; renewals then take turns under `refreshLock`. An item from before that, in
/// the app's own group, moves there the first time it's read. The Mac's file-based keychain has
/// no access groups, so there it stays the app's own.
public struct KeychainTokenStore: TokenStore {
    public struct KeychainError: Error, Equatable {
        public let status: OSStatus
    }

    private let service: String
    private let accessGroup: String?
    public let refreshLock: RefreshLock?

    public init(
        service: String = "Usual Bot gateway sign-in", accessGroup: String? = nil, refreshLock: RefreshLock? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.refreshLock = refreshLock
    }

    /// The app's and the share extension's store: shared through the App Group on iPhone, when
    /// the build has one.
    public static func forApp(bundle: Bundle = .main) -> KeychainTokenStore {
        #if os(iOS)
            if let group = ShareContainer.groupIdentifier(bundle: bundle),
                let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            {
                return KeychainTokenStore(
                    accessGroup: group, refreshLock: RefreshLock(url: folder.appending(path: "SignIn.lock")))
            }
        #endif
        return KeychainTokenStore()
    }

    public func load(for gateway: GatewayAddress) throws -> TokenSet? {
        if let accessGroup, let data = try find(baseQuery(for: gateway, group: accessGroup)) {
            return try JSONDecoder().decode(TokenSet.self, from: data)
        }
        guard let data = try find(baseQuery(for: gateway)) else { return nil }
        let tokens = try JSONDecoder().decode(TokenSet.self, from: data)
        if accessGroup != nil { try? move(data, for: gateway) }
        return tokens
    }

    public func save(_ tokens: TokenSet, for gateway: GatewayAddress) throws {
        let data = try JSONEncoder().encode(tokens)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery(for: gateway, group: accessGroup) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound, accessGroup != nil {
            // Still the app's own copy, which couldn't be moved: a renewal must land on it.
            status = SecItemUpdate(baseQuery(for: gateway) as CFDictionary, update as CFDictionary)
            if status == errSecSuccess { try? move(data, for: gateway) }
        }
        if status == errSecItemNotFound {
            try add(data, for: gateway)
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(for gateway: GatewayAddress) throws {
        // Without a group: every copy, the app's own and the shared one.
        let status = SecItemDelete(baseQuery(for: gateway) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func find(_ query: [String: Any]) throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return data
    }

    private func add(_ data: Data, for gateway: GatewayAddress) throws {
        var item = baseQuery(for: gateway, group: accessGroup)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecMissingEntitlement, accessGroup != nil {
            // A build signed without the group (the Simulator, say): the app's own group, unshared.
            item[kSecAttrAccessGroup as String] = nil
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Moves the app's own copy into the shared group. The copy is made before the old one goes,
    /// and reads look in the shared group first, so a failure part way can't lose the sign-in.
    private func move(_ data: Data, for gateway: GatewayAddress) throws {
        guard let accessGroup else { return }
        try add(data, for: gateway)
        guard try find(baseQuery(for: gateway, group: accessGroup)) != nil else { return }
        var query = baseQuery(for: gateway)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let copies = result as? [[String: Any]]
        else { return }
        for copy in copies {
            guard let group = copy[kSecAttrAccessGroup as String] as? String, group != accessGroup else { continue }
            SecItemDelete(baseQuery(for: gateway, group: group) as CFDictionary)
        }
    }

    private func baseQuery(for gateway: GatewayAddress, group: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: gateway.baseURL.absoluteString,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }
}
