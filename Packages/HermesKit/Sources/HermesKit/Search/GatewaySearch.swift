import Foundation
import Observation

/// One match from the gateway's `GET /api/sessions/search`: the best matching message of one
/// conversation of one profile. Hermes returns no message ID or time, only the conversation and a
/// snippet with the matched words between `>>>` and `<<<`.
struct GatewaySearchResult: Decodable, Equatable, Sendable {
    /// The conversation's live (compression tip) session ID.
    let sessionId: String
    /// The first session of the conversation, before any compression.
    let lineageRoot: String?
    /// `user` or `assistant` for a message; `tool` for a tool's output, `nil` for a title or ID match.
    let role: String?
    let snippet: String

    struct Page: Decodable, Sendable {
        let results: [GatewaySearchResult]
    }

    /// Whether this is a message in the agent's Bot Chat, the only chat the app shows.
    func isInBotChat(_ chatID: String) -> Bool {
        sessionId == chatID || lineageRoot == chatID
    }

    /// As a search result in the chat of `contactID`, or `nil` for anything but your messages
    /// and the agent's.
    func hit(in contactID: Contact.ID, query: MessageSearch) -> MessageHit? {
        let author: MessageHit.Author
        switch role {
        case "user": author = .you
        case "assistant": author = .agent
        default: return nil
        }
        let parsed = Self.parse(snippet)
        guard !parsed.text.isEmpty else { return nil }
        // Hermes's LIKE fallback marks nothing; show the query's words instead.
        let matches = parsed.matches.isEmpty ? query.snippet(of: parsed.text).matches : parsed.matches
        let words = MessageSearch.fold(parsed.text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let shown = Self.leadingUpTo(matches.first?.lowerBound, in: parsed.text, matches: matches)
        return MessageHit(
            contactID: contactID, itemID: nil, author: author, date: nil, snippet: shown.text, matches: shown.matches,
            needle: words.filter { $0.count >= 2 })
    }

    /// Starts the snippet a few words before `match` when it's too far in for a narrow row to
    /// show, as the device's own snippets do.
    static func leadingUpTo(
        _ match: String.Index?, in text: String, matches: [Range<String.Index>]
    ) -> (text: String, matches: [Range<String.Index>]) {
        guard let match, text.distance(from: text.startIndex, to: match) > 40 else { return (text, matches) }
        var start = text.index(match, offsetBy: -24)
        if let space = text[start..<match].firstIndex(of: " ") { start = text.index(after: space) }
        let cut = text.distance(from: text.startIndex, to: start)
        let shown = "…" + text[start...]
        let moved = matches.compactMap { range -> Range<String.Index>? in
            let lower = text.distance(from: text.startIndex, to: range.lowerBound) - cut + 1
            let upper = text.distance(from: text.startIndex, to: range.upperBound) - cut + 1
            guard lower >= 1 else { return nil }
            return shown.index(shown.startIndex, offsetBy: lower)..<shown.index(shown.startIndex, offsetBy: upper)
        }
        return (shown, moved)
    }

    /// The snippet as one line of plain text, and where Hermes marked its matches. FTS5 marks
    /// matches with `>>>` and `<<<` and cuts with `...`; the text is the message as stored, so
    /// Markdown marks and line breaks are taken out.
    static func parse(_ raw: String) -> (text: String, matches: [Range<String.Index>]) {
        var pieces: [(text: String, isMatch: Bool)] = []
        var rest = Substring(raw)
        while let open = rest.range(of: ">>>") {
            pieces.append((String(rest[..<open.lowerBound]), false))
            rest = rest[open.upperBound...]
            let close = rest.range(of: "<<<")
            pieces.append((String(rest[..<(close?.lowerBound ?? rest.endIndex)]), true))
            rest = close.map { rest[$0.upperBound...] } ?? ""
        }
        pieces.append((String(rest), false))

        var text = ""
        var marked: [Range<Int>] = []
        for piece in pieces {
            var clean = piece.text
            for mark in ["**", "__", "~~", "`"] { clean = clean.replacingOccurrences(of: mark, with: "") }
            clean = clean.replacing(/\s+/, with: " ")
            if clean.hasPrefix(" "), text.isEmpty || text.hasSuffix(" ") { clean.removeFirst() }
            let core = clean.trimmingCharacters(in: .whitespaces)
            if piece.isMatch, !core.isEmpty {
                let start = text.count + clean.prefix { $0 == " " }.count
                marked.append(start..<start + core.count)
            }
            text += clean
        }
        while text.hasSuffix(" ") { text.removeLast() }
        var dropped = 0
        if text.hasPrefix("...") {
            text = "…" + text.dropFirst(3)
            dropped = 2
        }
        if text.hasSuffix("...") { text = text.dropLast(3) + "…" }
        let matches = marked.compactMap { mark -> Range<String.Index>? in
            let start = mark.lowerBound - dropped
            let end = mark.upperBound - dropped
            guard start >= 0, end <= text.count, start < end else { return nil }
            return text.index(text.startIndex, offsetBy: start)..<text.index(text.startIndex, offsetBy: end)
        }
        return (text, matches)
    }
}

/// What the gateway found for the current search, chat by chat, as its answers arrive.
@MainActor
@Observable
final class GatewaySearch {
    /// The query the answers are for, trimmed.
    private(set) var query: String?
    /// The best match in each agent's Bot Chat that the gateway reported.
    private(set) var hits: [Contact.ID: MessageHit] = [:]
    /// Agents whose answer hasn't come yet.
    private(set) var waiting: Set<Contact.ID> = []
    /// The gateway has no search endpoint; asked once per sign-in.
    @ObservationIgnored var isUnsupported = false
    /// How long typing must pause before the gateway is asked. Tests set zero.
    @ObservationIgnored var delay: Duration = .milliseconds(350)
    /// Answers a search for one profile instead of the gateway: the demo and tests.
    @ObservationIgnored var fetch: ((_ profile: String, _ query: String) async throws -> [GatewaySearchResult])?
    @ObservationIgnored var task: Task<Void, Never>?

    /// Each profile's search returns at most this many conversations; the Bot Chat is one of
    /// them. 100 is the gateway's own cap (`search_sessions`'s `safe_limit`).
    static let resultLimit = 100
    /// Profiles asked at once.
    static let concurrency = 4

    func start(_ query: String, waitingOn ids: Set<Contact.ID>) {
        self.query = query
        hits = [:]
        waiting = ids
    }

    func receive(_ hit: MessageHit?, for id: Contact.ID, query: String) {
        guard query == self.query else { return }
        waiting.remove(id)
        if let hit { hits[id] = hit }
    }

    func clear() {
        task?.cancel()
        task = nil
        query = nil
        hits = [:]
        waiting = []
    }

    func reset() {
        clear()
        isUnsupported = false
    }
}
