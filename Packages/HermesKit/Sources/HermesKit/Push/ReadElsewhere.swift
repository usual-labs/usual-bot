import CryptoKit
import Foundation

extension PushRelay {
    /// The chat a silent push from the gateway says you read on another device, so this one can take
    /// down what it shows about it. `nil` for any other push, or one this device can't open.
    public nonisolated static func chatReadElsewhere(in userInfo: [AnyHashable: Any]) -> Contact.ID? {
        guard userInfo["kind"] as? String == "read", let sealed = userInfo["s"] as? String,
            let key = RelayKeychain.load()?.sealKey
        else { return nil }
        return chatReadElsewhere(sealed: sealed, key: key)
    }

    /// What `Integrations/hermes-push` seals: JSON under AES-GCM, as nonce, then ciphertext and tag.
    /// The kind inside is checked too, so a message's sealed text passed off as a clear opens nothing.
    nonisolated static func chatReadElsewhere(sealed: String, key: Data) -> Contact.ID? {
        struct Read: Decodable {
            let kind: String
            let chat: String
        }
        guard let data = Data(base64Encoded: sealed), let box = try? AES.GCM.SealedBox(combined: data),
            let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key)),
            let read = try? JSONDecoder().decode(Read.self, from: plain), read.kind == "read"
        else { return nil }
        return read.chat
    }
}
