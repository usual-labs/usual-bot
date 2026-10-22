import Foundation
import Security

/// Where a gateway's tokens are kept between launches.
public protocol TokenStore: Sendable {
    func load(for gateway: GatewayAddress) throws -> TokenSet?
    func save(_ tokens: TokenSet, for gateway: GatewayAddress) throws
    func delete(for gateway: GatewayAddress) throws
}

/// Stores tokens as a generic password in the Keychain, one item per gateway, readable only
/// after the device has been unlocked once and never synced or backed up to another device.
public struct KeychainTokenStore: TokenStore {
    public struct KeychainError: Error, Equatable {
        public let status: OSStatus
    }

    private let service: String

    public init(service: String = "Usual Bot gateway sign-in") {
        self.service = service
    }

    public func load(for gateway: GatewayAddress) throws -> TokenSet? {
        var query = baseQuery(for: gateway)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(TokenSet.self, from: data)
    }

    public func save(_ tokens: TokenSet, for gateway: GatewayAddress) throws {
        let data = try JSONEncoder().encode(tokens)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(for: gateway) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(for: gateway)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(for gateway: GatewayAddress) throws {
        let status = SecItemDelete(baseQuery(for: gateway) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(for gateway: GatewayAddress) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: gateway.baseURL.absoluteString,
        ]
    }
}
