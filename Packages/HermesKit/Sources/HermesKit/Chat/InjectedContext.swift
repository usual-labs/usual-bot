import Foundation

/// What Hermes adds to the end of a turn's message for the model alone: our plugin's
/// `<usual-bot-…>` lines and its own recalled memory. A text-only turn keeps it out of the
/// message, in the row's `api_content`; a turn with an image keeps it as a text part, which the
/// stored row flattens into the message's text after its `[Image attached at: …]` line (Hermes
/// #71998). So history can hand it back as if you'd written it.
enum InjectedContext {
    private static let tags = ["usual-bot-voice", "usual-bot-turn", "usual-bot-context", "memory-context"]

    /// The message without the blocks Hermes added after it; unchanged when it has none.
    static func strip(_ message: String) -> String {
        var text = Substring(message)
        var stripped = false
        while true {
            let trimmed = text.trimmingSuffix(while: \.isWhitespace)
            guard let tag = tags.first(where: { trimmed.hasSuffix("</\($0)>") }),
                let open = trimmed.range(of: "<\(tag)", options: .backwards),
                open.lowerBound == trimmed.startIndex || trimmed[trimmed.index(before: open.lowerBound)].isNewline
            else { break }
            text = trimmed[..<open.lowerBound]
            stripped = true
        }
        return stripped ? String(text.trimmingSuffix(while: \.isWhitespace)) : message
    }
}

extension Substring {
    fileprivate func trimmingSuffix(while drop: (Character) -> Bool) -> Substring {
        var end = endIndex
        while end > startIndex, drop(self[index(before: end)]) { end = index(before: end) }
        return self[..<end]
    }
}
