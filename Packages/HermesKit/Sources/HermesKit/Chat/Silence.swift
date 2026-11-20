import Foundation

/// A Bot's word for "nothing to say": a reply that is only `[SILENT]` or `NO_REPLY`. Hermes asks for
/// one when a routine finds nothing new, another Bot sends a note, or a background process ends,
/// and keeps it in the history as the model wrote it. Its own chats drop it before you see it
/// (`gateway/response_filters.py`); the app's chats get it as text, so the app drops it too.
public enum Silence {
    /// `LIVE_GATEWAY_SILENT_MARKERS`, with the Chinese forms a model may translate them into.
    private static let markers: Set<String> = [
        "[SILENT]", "SILENT", "NO_REPLY", "NO REPLY", "[静默]", "静默", "[沉默]", "沉默",
    ]
    /// Longer than any marker could be, even with stray punctuation.
    private static let lengthCap = 64

    /// Whether `text` is only a marker: the Bot chose not to reply. Prose that mentions one is a reply.
    public static func isMarker(_ text: String) -> Bool {
        candidates(text).contains { markers.contains($0) }
    }

    /// `text` without a marker on its own last line: "Done.\n\nNO_REPLY" is "Done.".
    public static func withoutClosingMarker(_ text: String) -> String {
        let (head, tail) = lastLine(of: text)
        return !head.isEmpty && isMarker(tail) ? head : text
    }

    /// What of a reply still streaming can show: nothing while it could still become a marker
    /// ("NO_RE"), and not a last line that could still become a closing one.
    public static func shownWhileStreaming(_ text: String) -> String {
        if isMarker(text) || isPartialMarker(text) { return "" }
        let (head, tail) = lastLine(of: text)
        return !head.isEmpty && (isMarker(tail) || isPartialMarker(tail)) ? head : text
    }

    private static func isPartialMarker(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, stripped.count <= lengthCap else { return false }
        let forms = candidates(text)
        return markers.contains { marker in forms.contains { marker.hasPrefix($0) } }
    }

    private static func candidates(_ text: String) -> [String] {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, stripped.count <= lengthCap else { return [] }
        // Stray punctuation round it (".NO_REPLY", "*NO_REPLY*"), but brackets stay: "[SILENT" isn't one.
        let edge = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "[]"))
        let bare = stripped.trimmingCharacters(in: edge).trimmingCharacters(in: .whitespaces)
        return Set([stripped, bare]).filter { !$0.isEmpty }.map { canonical($0) }
    }

    private static func canonical(_ text: String) -> String {
        text.uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func lastLine(of text: String) -> (head: String, tail: String) {
        let trimmed = text.replacing(/\s+$/, with: "")
        guard let newline = trimmed.lastIndex(of: "\n") else { return ("", trimmed) }
        let head = String(trimmed[..<newline]).replacing(/\s+$/, with: "")
        return (head, String(trimmed[trimmed.index(after: newline)...]))
    }
}
