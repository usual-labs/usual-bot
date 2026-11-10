import Foundation

/// Cuts a reply that's still streaming into sentences to speak, as plain words: no Markdown
/// marks, no code, no file lines. Fed the whole reply so far each time; gives back only what's new.
struct SpokenReply {
    /// Characters of the reply already handled.
    private var consumed = 0
    /// Text after the last complete sentence, waiting for more.
    private var pending = ""
    private var inCode = false

    /// The new complete sentences in `reply`. With `final`, everything left goes out too.
    mutating func sentences(in reply: String, final: Bool) -> [String] {
        guard reply.count >= consumed else { return [] }
        pending += reply.dropFirst(consumed)
        consumed = reply.count
        var out: [String] = []
        // Whole lines first: code fences and file lines are judged by line.
        while let newline = pending.firstIndex(of: "\n") {
            out += line(String(pending[..<newline]))
            pending.removeSubrange(...newline)
        }
        // Then finished sentences on the line still arriving.
        if !inCode, !final, let end = Self.lastSentenceEnd(in: pending) {
            out += Self.split(Self.plain(String(pending[..<end])))
            pending.removeSubrange(..<end)
        }
        if final {
            out += line(pending)
            pending = ""
        }
        return out
    }

    private mutating func line(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if Self.isFence(trimmed) {
            inCode.toggle()
            return []
        }
        guard !inCode, !Self.isUnspoken(trimmed) else { return [] }
        return Self.split(Self.plain(Self.cells(trimmed)))
    }

    private static func isFence(_ line: String) -> Bool { line.hasPrefix("```") || line.hasPrefix("~~~") }

    /// File and delivery lines, and the rules of tables and sections: nothing a voice would say.
    private static func isUnspoken(_ line: String) -> Bool {
        line.hasPrefix("MEDIA:") || line.hasPrefix("@image:") || line.hasPrefix("@file:")
            || MarkdownBlock.isDeliveryMarker(line) || !line.contains { $0.isLetter || $0.isNumber }
    }

    /// A table row as its cells with commas between; any other line unchanged.
    private static func cells(_ line: String) -> String {
        guard line.hasPrefix("|"), line.hasSuffix("|"), line.count > 1 else { return line }
        return line.dropFirst().dropLast().split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Whether any of `markdown` would be spoken: not a reply that's only code or a file. Cheap
    /// enough to ask for every message on screen.
    static func hasWords(in markdown: String) -> Bool {
        var inCode = false
        for line in markdown.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFence(trimmed) {
                inCode.toggle()
            } else if !inCode, !isUnspoken(trimmed) {
                return true
            }
        }
        return false
    }

    /// Where the last sentence on a line ends (after its `.`, `!` or `?` and the space after it).
    private static func lastSentenceEnd(in text: String) -> String.Index? {
        var found: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if ".!?".contains(text[index]), next < text.endIndex, text[next] == " " { found = next }
            index = next
        }
        return found
    }

    /// Sentences in one piece of plain text.
    static func split(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences
    }

    /// Markdown as it would be read aloud: list and heading marks, emphasis and inline code
    /// marks dropped, links read by their text, web addresses as "a link", file paths as the file's name.
    static func plain(_ markdown: String) -> String {
        var text = markdown
        let rules: [(String, String)] = [
            (#"^\s{0,3}(#{1,6}|[-*+]|\d+[.)]|>)\s+"#, ""),
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"https?://\S+"#, String(localized: "a link")),
            // A file's name, not the folders it's in.
            (#"(?<![\w/.~])(?:~/(?:[\w.@+\-]+/)*|(?:/[\w.@+\-]+)+/)([\w.@+\-]+)/?"#, "$1"),
            (#"(\*\*|__|\*|_|`|~~)"#, ""),
            (#"\s+"#, " "),
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
