import Foundation
import Observation
import Security
import os

/// This device's place in Usual's push relay (`Services/push-relay`). Apple's token goes to the
/// relay, which answers with an ID and two secrets: one lets this device update its entry, the other
/// lets its gateway push to it. The seal key never leaves this device and its gateway, so the relay
/// and Apple carry notifications they can't read.
@MainActor
@Observable
public final class PushRelay {
    public enum Phase: Equatable, Sendable {
        /// This build has no relay, or no push entitlement.
        case unavailable
        case waiting
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase
    public private(set) var registration: Registration?

    public struct Registration: Codable, Sendable, Equatable {
        public let id: String
        let secret: String
        public let sendKey: String
        /// Seals what the gateway sends this device. Made here; the relay never has it.
        public let sealKey: Data
        var token: String
        var environment: String
    }

    private let relay: URL?
    private let environment: String
    private let session: URLSession
    private static let log = Logger(subsystem: "UsualBot", category: "push-relay")

    /// The relay's address comes from the build (`UsualPushRelayURL` in Info.plist); a build
    /// without one has no push.
    public init(relay: URL?, environment: String, session: URLSession = .shared) {
        self.relay = relay
        self.environment = environment == "production" ? "production" : "sandbox"
        self.session = session
        registration = RelayKeychain.load()
        phase = relay == nil ? .unavailable : .waiting
    }

    /// Already signed up, without the keychain: for tests.
    init(relay: URL, registration: Registration) {
        self.relay = relay
        environment = registration.environment
        session = .shared
        self.registration = registration
        phase = .ready
    }

    public static func fromMainBundle() -> PushRelay {
        let info = Bundle.main.infoDictionary ?? [:]
        let address = (info["UsualPushRelayURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        #if os(macOS)
            let profile = Bundle.main.bundleURL.appending(path: "Contents/embedded.provisionprofile")
        #else
            let profile = Bundle.main.bundleURL.appending(path: "embedded.mobileprovision")
        #endif
        return PushRelay(relay: address, environment: appleEnvironment(profile: try? Data(contentsOf: profile)))
    }

    /// Which of Apple's push services this copy is signed for: its provisioning profile says.
    /// Xcode signs builds for the sandbox and switches to production when it exports for TestFlight
    /// or the App Store, so no build setting can know. TestFlight and App Store iPhone apps carry
    /// no profile, and use production.
    nonisolated static func appleEnvironment(profile: Data?) -> String {
        guard let profile else { return "production" }
        // A profile is a signed wrapper around a property list.
        guard let start = profile.range(of: Data("<?xml".utf8)),
            let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
            let list = try? PropertyListSerialization.propertyList(
                from: profile[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
            let entitlements = list["Entitlements"] as? [String: Any]
        else { return "sandbox" }
        let environment =
            entitlements["com.apple.developer.aps-environment"] ?? entitlements["aps-environment"]
        return environment as? String == "production" ? "production" : "sandbox"
    }

    public var isAvailable: Bool { relay != nil }
    /// Where the gateway sends this device's notifications.
    public var address: URL? { relay }

    /// Apple's token for this install. Registers once, then only says when the token changes.
    public func received(token data: Data) async {
        guard let relay else { return }
        let token = data.map { String(format: "%02x", $0) }.joined()
        do {
            if var known = registration {
                if known.token != token || known.environment != environment {
                    try await call(
                        relay.appending(path: "v1/devices/\(known.id)"), method: "PUT", bearer: known.secret,
                        body: ["token": token, "environment": environment])
                    known.token = token
                    known.environment = environment
                    try save(known)
                }
            } else {
                let answer: Registered = try await call(
                    relay.appending(path: "v1/devices"), method: "POST",
                    body: ["token": token, "environment": environment])
                try save(
                    Registration(
                        id: answer.id, secret: answer.secret, sendKey: answer.sendKey, sealKey: Self.newKey(),
                        token: token, environment: environment))
            }
            phase = .ready
        } catch RelayError.status(404) where registration != nil {
            // The relay forgot this device (Apple said its token was dead): start again.
            RelayKeychain.delete()
            registration = nil
            await received(token: data)
        } catch {
            Self.log.error("Couldn't register for push: \(error.localizedDescription, privacy: .public)")
            phase = .failed(String(localized: "Couldn’t reach the push relay. Try again later."))
        }
    }

    public func failedToRegister(_ error: Error) {
        guard relay != nil else { return }
        Self.log.error("Apple refused push: \(error.localizedDescription, privacy: .public)")
        phase = .failed(String(localized: "This device couldn’t sign up for notifications."))
    }

    /// Sends a test straight from this device through the relay, which tests Apple and the relay
    /// without a gateway. Answers the relay's verdict, such as "sent".
    public func sendTest() async throws -> String {
        guard let relay, let registration else { throw RelayError.notRegistered }
        let push = Push(device: registration.id, key: registration.sendKey, kind: "test")
        let answer: Sent = try await call(
            relay.appending(path: "v1/send"), method: "POST", body: Pushes(pushes: [push]))
        return answer.results.first.map { [$0.status, $0.reason].compactMap(\.self).joined(separator: ": ") } ?? "?"
    }

    // MARK: Wire

    enum RelayError: Error {
        case status(Int)
        case notRegistered
    }

    private struct Registered: Decodable, Sendable {
        let id: String
        let secret: String
        let sendKey: String
    }

    private struct Push: Encodable, Sendable {
        let device: String
        let key: String
        let kind: String
    }

    private struct Pushes: Encodable, Sendable {
        let pushes: [Push]
    }

    private struct Sent: Decodable, Sendable {
        struct Result: Decodable, Sendable {
            let status: String
            let reason: String?
        }
        let results: [Result]
    }

    private struct Done: Decodable, Sendable {}

    private func call(_ url: URL, method: String, bearer: String? = nil, body: some Encodable & Sendable) async throws {
        let _: Done = try await call(url, method: method, bearer: bearer, body: body)
    }

    private func call<T: Decodable & Sendable>(
        _ url: URL, method: String, bearer: String? = nil, body: some Encodable & Sendable
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw RelayError.status(status) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func save(_ new: Registration) throws {
        try RelayKeychain.save(new)
        registration = new
    }

    private static func newKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

/// The registration, kept on this device only and never backed up: a restored backup would hold
/// another install's keys. In a keychain group the notification extension shares
/// (`UsualPushKeychainGroup`), so it can open what the gateway sealed.
enum RelayKeychain {
    private static var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Usual Bot push relay",
            kSecAttrAccount as String: "device",
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let group = Bundle.main.object(forInfoDictionaryKey: "UsualPushKeychainGroup") as? String,
            !group.isEmpty, !group.hasPrefix(".")
        {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    static func load() -> PushRelay.Registration? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(PushRelay.Registration.self, from: data)
    }

    static func save(_ registration: PushRelay.Registration) throws {
        let data = try JSONEncoder().encode(registration)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainTokenStore.KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainTokenStore.KeychainError(status: status)
        }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
