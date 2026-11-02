import Foundation

/// The name you give a new Bot, and the Hermes profile name made from it. Hermes takes only
/// `^[a-z0-9][a-z0-9_-]{0,63}$` (`hermes_constants.PROFILE_ID_RE`), so, as in the official app,
/// "Throwaway Test" becomes `throwaway-test` and the name you typed is kept as the Bot's title.
public struct BotName: Equatable, Sendable {
    /// The name as typed, trimmed: what the app shows.
    public let title: String
    /// The profile name: the Bot's ID on the gateway, which never changes after this.
    public let profile: String

    /// Names Hermes refuses for a profile (`hermes_cli.profiles._RESERVED_NAMES`).
    static let reserved: Set<String> = ["hermes", "default", "test", "tmp", "root", "sudo"]
    static let longest = 64

    public init(_ typed: String) {
        title = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        profile = Self.slug(title)
    }

    /// Why this name can't make a Bot yet, in words for the form; `nil` when it can. `taken` are the
    /// profile names already on the gateway.
    public func problem(taken: Set<String>) -> String? {
        if title.isEmpty { return String(localized: "Give your Bot a name.") }
        if profile.isEmpty { return String(localized: "Use at least one letter or number in the name.") }
        if Self.reserved.contains(profile) {
            return String(localized: "Hermes keeps the name “\(profile)” for itself. Try another name.")
        }
        if taken.contains(profile) {
            return String(localized: "There's already a Bot called “\(profile)” on this gateway. Try another name.")
        }
        return nil
    }

    /// The official app's `slugifyProfileName`: accented letters fold to their base letter, any other
    /// letter or digit becomes a `u<hex>` token (`小助手` → `u5c0f-u52a9-u624b`), everything else
    /// becomes a dash, and a name too long is cut at a dash so no token is split.
    static func slug(_ name: String) -> String {
        var folded = ""
        for character in name.precomposedStringWithCanonicalMapping {
            guard character.isLetter || character.isNumber else {
                folded.append(character)
                continue
            }
            let base = String(character).decomposedStringWithCompatibilityMapping.unicodeScalars
                .filter { !$0.properties.isDiacritic && $0.properties.generalCategory != .nonspacingMark }
            if !base.isEmpty,
                base.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) })
            {
                folded.unicodeScalars.append(contentsOf: base)
            } else {
                let hex = character.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-u")
                folded += "-u\(hex)-"
            }
        }
        var slug = ""
        for scalar in folded.lowercased().unicodeScalars {
            let allowed =
                scalar.isASCII && (("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_")
            if allowed {
                slug.unicodeScalars.append(scalar)
            } else if !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        slug = String(slug.drop { $0 == "-" || $0 == "_" }.reversed().drop { $0 == "-" }.reversed())
        guard slug.count > longest else { return slug }
        let cut = slug.prefix(longest)
        let boundary =
            slug[slug.index(slug.startIndex, offsetBy: longest)] == "-"
            ? cut.endIndex : (cut.lastIndex(of: "-") ?? cut.endIndex)
        return String(cut[..<boundary].reversed().drop { $0 == "-" }.reversed())
    }
}
