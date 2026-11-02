import Foundation

/// A message that matches a search, in one chat or room.
public struct MessageHit: Identifiable, Equatable, Sendable {
    public enum Author: Equatable, Sendable {
        case you
        /// The chat's agent.
        case agent
        /// A room member, by the name the sidebar gives it.
        case member(String)
    }

    public let contactID: Contact.ID
    /// The transcript item to scroll to, or `nil` for a message the gateway found in history this
    /// device hasn't loaded: `AppModel.locate(_:)` loads the chat and finds it.
    public let itemID: Int?
    public let author: Author
    /// When it was said, when known. The gateway doesn't say for the messages it finds.
    public let date: Date?
    /// One line of the message around its first match, as plain text.
    public let snippet: String
    /// Where the query's words are in `snippet`.
    public let matches: [Range<String.Index>]
    /// The gateway's snippet as folded words, to find the message once its chat is loaded.
    let needle: [String]

    init(
        contactID: Contact.ID, itemID: Int?, author: Author, date: Date?, snippet: String,
        matches: [Range<String.Index>], needle: [String] = []
    ) {
        self.contactID = contactID
        self.itemID = itemID
        self.author = author
        self.date = date
        self.snippet = snippet
        self.matches = matches
        self.needle = needle
    }

    /// Found by the gateway in history this device hasn't loaded.
    public var isEarlier: Bool { itemID == nil }

    /// The gateway reports one match per chat, so a chat has at most one hit without an item.
    public var id: String { itemID.map { "\(contactID)#\($0)" } ?? "\(contactID)#earlier" }
}

/// Where a search result is, once its chat has loaded.
public enum MessageLocation: Equatable, Sendable {
    /// The transcript item to scroll to.
    case item(Int)
    /// It can't be shown, and why, in words for the reader.
    case unavailable(String)
}

/// What a search looks for: every word of the query, in any order, ignoring case and accents.
public struct MessageSearch: Sendable {
    /// Shorter queries match too much to be worth showing.
    public static let minimumLength = 2

    /// The query's words, folded.
    let words: [String]
    private let needles: [[UInt8]]

    /// `nil` when the query is too short to search messages with.
    public init?(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumLength else { return nil }
        words = Self.fold(trimmed).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        needles = words.map { Array($0.utf8) }
    }

    /// Whether a message folded with `fold` holds every word.
    func matches(folded: [UInt8]) -> Bool {
        needles.allSatisfy { Self.contains($0, in: folded) }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func contains(_ needle: [UInt8], in haystack: [UInt8]) -> Bool {
        guard let first = needle.first, needle.count <= haystack.count else { return needle.isEmpty }
        var start = 0
        let last = haystack.count - needle.count
        while start <= last {
            if haystack[start] == first {
                var offset = 1
                while offset < needle.count, haystack[start + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return true }
            }
            start += 1
        }
        return false
    }

    // MARK: - Text

    /// What a reader sees of a message, on one line: no attachment, `MEDIA:` or quoted lines, and
    /// no Markdown marks. Searching this keeps the snippet showing what matched.
    static func plain(_ text: String) -> String {
        var lines = AttachmentRef.split(text).text.split(whereSeparator: \.isNewline).map(String.init)
        // A reply's quote is another message, which has its own hit.
        while let first = lines.first, first.hasPrefix("> ") { lines.removeFirst() }
        let words = lines.compactMap { line -> String? in
            guard var line = SpokenAudio.withoutSpeechPaths(Substring(line.trimmingCharacters(in: .whitespaces)))
            else { return nil }
            if line.hasPrefix("MEDIA:") { return nil }
            for mark in ["#", ">", "- ", "* ", "+ "] {
                while line.hasPrefix(mark) { line = String(line.dropFirst(mark.count)) }
                line = line.trimmingCharacters(in: .whitespaces)
            }
            for mark in ["**", "__", "~~", "`"] { line = line.replacingOccurrences(of: mark, with: "") }
            return line.isEmpty ? nil : line
        }
        return words.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The part of `plain` around the query's first word to appear, and where each word falls in it.
    func snippet(of plain: String) -> (text: String, matches: [Range<String.Index>]) {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        let first = words.compactMap { plain.range(of: $0, options: options)?.lowerBound }.min() ?? plain.startIndex
        // From the start when the match is close to it; else a little of what comes before, from a word.
        var start = plain.startIndex
        if plain.distance(from: plain.startIndex, to: first) > Self.reach {
            start = plain.index(first, offsetBy: -Self.lead)
            if let space = plain[start..<first].firstIndex(of: " ") { start = plain.index(after: space) }
        }
        let end = plain.index(start, offsetBy: Self.length, limitedBy: plain.endIndex) ?? plain.endIndex
        var text = String(plain[start..<end])
        if start > plain.startIndex { text = "…" + text }
        if end < plain.endIndex { text += "…" }
        var matches: [Range<String.Index>] = []
        for word in words {
            var from = text.startIndex
            while let found = text.range(of: word, options: options, range: from..<text.endIndex) {
                matches.append(found)
                from = found.upperBound
            }
        }
        return (text, matches.sorted { $0.lowerBound < $1.lowerBound })
    }

    /// A match this far in still shows in a narrow row, so the snippet starts at the beginning.
    private static let reach = 40
    /// Characters kept before a match further in.
    private static let lead = 24
    /// More than a row shows; the row cuts it off.
    private static let length = 160
}

/// Each chat's messages ready to search, rebuilt only when its transcript changes.
@MainActor
final class MessageIndex {
    struct Message {
        let itemID: Int
        let author: Author
        let date: Date?
        let plain: String
        let folded: [UInt8]
    }

    enum Author {
        case you, agent
        case member(id: String)
    }

    /// Enough to tell a transcript changed: items are appended, removed or renumbered, and the
    /// text of a message never changes in place.
    private struct Signature: Equatable {
        let count: Int
        let first: Int?
        let last: Int?
    }

    private var entries: [Contact.ID: (signature: Signature, messages: [Message])] = [:]

    /// `id`'s messages, oldest first: yours and the agents' text, not tool steps or Hermes's notes.
    func messages(of id: Contact.ID, items: [TranscriptItem]) -> [Message] {
        let signature = Signature(count: items.count, first: items.first?.id, last: items.last?.id)
        if let entry = entries[id], entry.signature == signature { return entry.messages }
        let messages = items.compactMap { item -> Message? in
            let author: Author
            let text: String
            switch item.content {
            case .user(let body): (author, text) = (.you, body)
            case .assistant(let body): (author, text) = (.agent, body)
            case .member(let member, let body): (author, text) = (.member(id: member), body)
            default: return nil
            }
            let plain = MessageSearch.plain(text)
            guard !plain.isEmpty else { return nil }
            return Message(
                itemID: item.id, author: author, date: item.date, plain: plain,
                folded: Array(MessageSearch.fold(plain).utf8))
        }
        entries[id] = (signature, messages)
        return messages
    }

    /// Forgets chats that are gone.
    func keep(only ids: Set<Contact.ID>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}
