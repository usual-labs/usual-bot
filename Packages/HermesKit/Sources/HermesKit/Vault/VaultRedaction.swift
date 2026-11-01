import Foundation

/// Keeps secrets out of what the app shows. The gateway scrubs its vault errors, but a password
/// manager's own error text passes through it, so the app scrubs again before showing any of it.
enum VaultRedaction {
    private static let hidden = "[hidden]"

    /// `text` without `secrets`, `password=…`-style pairs, or anything shaped like a card number.
    static func scrub(_ text: String, removing secrets: [String] = []) -> String {
        var scrubbed = text
        // Longest first: a shorter secret inside a longer one mustn't leave the rest behind.
        for secret in secrets.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            scrubbed = scrubbed.replacingOccurrences(of: secret, with: hidden, options: .caseInsensitive)
        }
        scrubbed = scrubbed.replacingOccurrences(
            of: #"(?i)((?:password|passwd|secret|token|otp|cvc|code)["']?\s*[:=]\s*)\S+"#, with: "$1\(hidden)",
            options: .regularExpression)
        return scrubbed.replacingOccurrences(
            of: #"\b\d(?:[ -]?\d){11,18}\b"#, with: hidden, options: .regularExpression)
    }
}
