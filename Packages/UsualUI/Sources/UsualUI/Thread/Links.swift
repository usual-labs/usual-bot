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

    /// The address a link attribute names: for `[the guide](https://…)` the target, not the words.
    /// A `.link` is a `URL`, or a `String` where AppKit kept the text as it was written.
    static func url(from link: Any?) -> URL? {
        (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
    }

    /// Whether this Mac or iPhone can open it. A Markdown link to a path names a file on the
    /// gateway, which it can't.
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme else { return false }
        return scheme != "file"
    }

    /// Where the links in `text` go, in reading order, each once.
    static func urls(in text: AttributedString) -> [URL] {
        var seen: Set<URL> = []
        return text.runs[\.link].compactMap { link, _ in
            guard let link, seen.insert(link).inserted else { return nil }
            return link
        }
    }

    /// Where the links in a reply go, in reading order, each once. Code has none.
    static func urls(in blocks: [MarkdownBlock]) -> [URL] {
        var seen: Set<URL> = []
        var all: [URL] = []
        for block in blocks {
            let texts: [AttributedString]
            switch block {
            case .paragraph(let text), .heading(_, let text), .listItem(_, _, let text), .quote(let text):
                texts = [text]
            case .table(let table):
                texts = table.header + table.rows.flatMap { $0 }
            default:
                continue
            }
            for url in texts.flatMap(urls(in:)) where seen.insert(url).inserted { all.append(url) }
        }
        return all
    }

    /// Where the addresses typed in a plain message, such as your own, go.
    static func urls(inPlain text: String) -> [URL] {
        urls(in: detect(in: text))
    }

    /// A link as a few words for a menu: `docs.example.com/search/limits`.
    static func shortName(_ url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        let path = url.path == "/" ? "" : url.path
        let name = (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + path
        return name.count > 40 ? name.prefix(39) + "…" : name
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
