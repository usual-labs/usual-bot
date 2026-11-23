import CryptoKit
import Foundation

extension PushRelay {
    /// A chat read on another device, as a silent push from a gateway says.
    public struct ReadElsewhere: Equatable, Sendable {
        public let chat: Contact.ID
        /// Which of this device's gateways (`SavedGateway.id`); `nil` from a plugin before 0.5.0.
        public let gateway: String?
    }

    /// A chat with something new, as a message or "needs you" notification that woke the app says
    /// (the relay's `wake`).
    public struct News: Equatable, Sendable {
        public let chat: Contact.ID
        /// Which of this device's gateways (`SavedGateway.id`); `nil` from a plugin before 0.5.0.
        public let gateway: String?
    }

    /// The chat a silent push from the gateway says you read on another device, so this one can take
    /// down what it shows about it. `nil` for any other push, or one this device can't open.
    public nonisolated static func chatReadElsewhere(in userInfo: [AnyHashable: Any]) -> ReadElsewhere? {
        guard userInfo["kind"] as? String == "read", let sealed = userInfo["s"] as? String,
            let key = RelayKeychain.load()?.sealKey
        else { return nil }
        return chatReadElsewhere(sealed: sealed, key: key)
    }

    /// The chat a notification that woke the app is about. `nil` for a clear or a test, or one this
    /// device can't open. The app gets the push as Apple delivered it, not as the notification
    /// extension changed it, so it opens the sealed text itself.
    public nonisolated static func news(in userInfo: [AnyHashable: Any]) -> News? {
        guard let kind = userInfo["kind"] as? String, newsKinds.contains(kind), let sealed = userInfo["s"] as? String,
            let key = RelayKeychain.load()?.sealKey
        else { return nil }
        return news(sealed: sealed, key: key)
    }

    private nonisolated static let newsKinds: Set<String> = ["message", "needs_you"]

    /// The kind inside is checked too, so a clear's sealed text passed off as a message opens nothing.
    nonisolated static func news(sealed: String, key: Data) -> News? {
        guard let opened = open(sealed, key: key), let chat = opened.chat, newsKinds.contains(opened.kind ?? "message")
        else { return nil }
        return News(chat: chat, gateway: opened.gateway)
    }

    /// The kind inside is checked too, so a message's sealed text passed off as a clear opens nothing.
    nonisolated static func chatReadElsewhere(sealed: String, key: Data) -> ReadElsewhere? {
        guard let opened = open(sealed, key: key), let chat = opened.chat, opened.kind == "read" else { return nil }
        return ReadElsewhere(chat: chat, gateway: opened.gateway)
    }

    private struct Opened: Decodable {
        let kind: String?
        let chat: String?
        let gateway: String?
    }

    /// What `Integrations/usual-bot` seals: JSON under AES-GCM, as nonce, then ciphertext and tag.
    private nonisolated static func open(_ sealed: String, key: Data) -> Opened? {
        guard let data = Data(base64Encoded: sealed), let box = try? AES.GCM.SealedBox(combined: data),
            let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key))
        else { return nil }
        return try? JSONDecoder().decode(Opened.self, from: plain)
    }
}
