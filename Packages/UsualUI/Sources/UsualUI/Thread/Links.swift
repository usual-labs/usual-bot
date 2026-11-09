import Foundation
import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Web addresses and email addresses typed out in a message, made into links.
enum Links {
    /// `text` with its bare addresses linked. Inline code and existing links stay as they are.
    static func detect(in text: AttributedString) -> AttributedString {
        let string = String(text.characters)
        guard let detector, string.contains(where: { $0 == "." || $0 == "@" }) else { return text }
        var text = text
        for match in detector.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
            guard let url = match.url, let found = Range(match.range, in: string),
                isWritten(String(string[found]), as: url)
            else { continue }
            let start = string.unicodeScalars.distance(from: string.startIndex, to: found.lowerBound)
            let count = string.unicodeScalars.distance(from: found.lowerBound, to: found.upperBound)
            let lower = text.unicodeScalars.index(text.startIndex, offsetBy: start)
            let range = lower..<text.unicodeScalars.index(lower, offsetBy: count)
            let taken = text[range].runs.contains {
                $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true
            }
            if !taken { text[range].link = url }
        }
        return text
    }

    /// Plain text, such as your own message, with its addresses linked.
    static func detect(in text: String) -> AttributedString {
        detect(in: AttributedString(text))
    }

    /// Only what reads as an address: `https://…`, `www.…` or `name@host`. The detector also
    /// takes file names such as `README.md` for web sites (`.md` is a country's domain).
    private static func isWritten(_ found: String, as url: URL) -> Bool {
        let lowered = found.lowercased()
        if url.scheme == "mailto" { return found.contains("@") }
        return lowered.contains("://") || lowered.hasPrefix("www.")
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}

extension Theme {
    /// A link in a reply: the system's link colour, and underlined wherever it's drawn.
    #if canImport(AppKit)
        static let link = Color(nsColor: .linkColor)
    #else
        static let link = Color(uiColor: .link)
    #endif
}

extension AttributedString {
    /// Underlines the links, so they stand out from the words around them in any colour.
    func underliningLinks() -> AttributedString {
        var text = self
        for (link, range) in text.runs[\.link] where link != nil {
            text[range].underlineStyle = .single
        }
        return text
    }
}
