import CryptoKit
import Foundation
import Security

/// A PKCE verifier and its S256 challenge (RFC 7636).
struct PKCE: Sendable {
    let verifier: String
    let challenge: String

    init(verifier: String) {
        self.verifier = verifier
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// 32 random bytes, base64url-encoded: a 43-character verifier.
    static func random() -> PKCE {
        PKCE(verifier: randomToken(byteCount: 32))
    }

    /// A random base64url string, also used for the CSRF `state`.
    static func randomToken(byteCount: Int = 24) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "The system random number generator failed")
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
