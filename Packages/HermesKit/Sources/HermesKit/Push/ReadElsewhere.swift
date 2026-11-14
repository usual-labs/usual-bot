import CryptoKit
import Foundation

extension PushRelay {
    /// A chat read on another device, as a silent push from a gateway says.
    public struct ReadElsewhere: Equatable, Sendable {
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

    /// What `Integrations/hermes-push` seals: JSON under AES-GCM, as nonce, then ciphertext and tag.
    /// The kind inside is checked too, so a message's sealed text passed off as a clear opens nothing.
    nonisolated static func chatReadElsewhere(sealed: String, key: Data) -> ReadElsewhere? {
        struct Read: Decodable {
            let kind: String
            let chat: String
            let gateway: String?
        }
        guard let data = Data(base64Encoded: sealed), let box = try? AES.GCM.SealedBox(combined: data),
            let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key)),
            let read = try? JSONDecoder().decode(Read.self, from: plain), read.kind == "read"
        else { return nil }
        return ReadElsewhere(chat: read.chat, gateway: read.gateway)
    }
}
