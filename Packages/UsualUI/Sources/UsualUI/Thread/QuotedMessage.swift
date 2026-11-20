import HermesKit
import SwiftUI

/// A message you're replying to, or words you picked from one: shown above the message box, then
/// sent as `>` quote lines, each with your answer to it under it, before the rest of your text. In
/// a room the reply also @mentions the author, so only it answers.
struct QuotedMessage: Hashable {
    let author: String
    /// One line, for the chip above the message box.
    let excerpt: String
    /// The room member to address; `nil` in a chat with one agent.
    var mention: String?
    /// The lines sent as the quote: the excerpt, or the words you selected.
    private var quoted: [String]
    /// What you said to this quote alone; it goes under it.
    var note = ""

    /// Part of a message you selected, kept whole and line by line: you picked those words.
    init(author: String, selection: String, mention: String? = nil, note: String = "") {
        self.author = author
        self.mention = mention
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        quoted = selection.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let flat = quoted.joined(separator: " ")
        excerpt = flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
    }

    init(author: String, text: String, mention: String? = nil) {
        self.author = author
        self.mention = mention
        // Plain words: no attachment, `MEDIA:` or widget lines, no Markdown marks.
        let lines = AttachmentRef.split(text).text.split(whereSeparator: \.isNewline)
            .filter {
                !$0.trimmingCharacters(in: .whitespaces).hasPrefix("MEDIA:") && !MarkdownBlock.isDeliveryMarker($0)
                    && WidgetDirective.parse($0) == nil
            }
        let joined = lines.joined(separator: " ")
        let flat =
            (try? AttributedString(
                markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            .map { String($0.characters) } ?? joined
        excerpt = flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
        quoted = [excerpt]
    }

    /// What you said, without the spaces around it: the chip's field edits `note` as you type.
    var reply: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The same words from the same author, whatever you said to them.
    func isSameQuote(as other: QuotedMessage) -> Bool {
        author == other.author && quoted == other.quoted && mention == other.mention
    }

    /// Its `>` lines, the author's name on the first, then your answer to it.
    fileprivate var block: String {
        let lines = quoted.enumerated().map { index, line in index == 0 ? "> \(author): \(line)" : "> \(line)" }
        return lines.joined(separator: "\n") + (reply.isEmpty ? "" : "\n\n" + reply)
    }

    /// A sent message in the order it reads: quotes, each run of `> ` lines on one line, and your
    /// words between and after them. Only a message that starts with a quote has any, and only
    /// `> Name: ` starts one, so a Markdown quote of your own in the middle stays your words.
    enum Part: Equatable {
        case quote(String)
        case text(String)

        var isQuote: Bool {
            if case .quote = self { true } else { false }
        }
    }

    static func parts(_ text: String) -> [Part] {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first(where: { !$0.allSatisfy(\.isWhitespace) }), startsQuote(first) else {
            return text.isEmpty ? [] : [.text(text)]
        }
        var parts: [Part] = []
        var words: [String] = []
        func endWords() {
            let joined = words.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { parts.append(.text(joined)) }
            words = []
        }
        var rest = lines[...]
        while let line = rest.first {
            // A quote follows a blank line, or starts the message.
            if startsQuote(line), words.last?.allSatisfy(\.isWhitespace) ?? true {
                endWords()
                let block = rest.prefix { $0.hasPrefix("> ") }
                parts.append(.quote(block.map { $0.dropFirst(2) }.joined(separator: " ")))
                rest = rest.dropFirst(block.count)
            } else {
                words.append(line)
                rest = rest.dropFirst()
            }
        }
        endWords()
        return parts
    }

    /// `> Name: words`, as `block` writes a quote's first line.
    private static func startsQuote(_ line: String) -> Bool {
        line.wholeMatch(of: /> [^:]{1,80}: .*/) != nil
    }

    /// The quotes in a sent message, and your words around them, in order, one after another.
    static func split(_ text: String) -> (quotes: [String], text: String) {
        let parts = parts(text)
        let quotes = parts.compactMap { if case .quote(let quote) = $0 { quote } else { nil } }
        guard !quotes.isEmpty else { return ([], text) }
        let words = parts.compactMap { if case .text(let words) = $0 { words } else { nil } }
        return (quotes, words.joined(separator: "\n\n"))
    }
}

extension [QuotedMessage] {
    /// Adds a quote after the ones waiting. The same words twice are one quote, and what you said
    /// to them the second time replaces what you said the first.
    mutating func add(_ quote: QuotedMessage) {
        if let index = firstIndex(where: { $0.isSameQuote(as: quote) }) {
            if !quote.reply.isEmpty { self[index].note = quote.reply }
        } else {
            append(quote)
        }
    }

    /// Your message with the quotes in front, a blank line between them so each stays its own. In
    /// a room it addresses each quoted member once.
    func message(_ text: String) -> String {
        guard !isEmpty else { return text }
        var mentions: [String] = []
        for mention in compactMap(\.mention) where !mentions.contains(mention) { mentions.append(mention) }
        let reply = (mentions.map { "@\($0)" } + (text.isEmpty ? [] : [text])).joined(separator: " ")
        return (map(\.block) + (reply.isEmpty ? [] : [reply])).joined(separator: "\n\n")
    }
}

/// What your message will be, above the message box: a message you're replying to, words you
/// quoted from one and what you said to them, or that you're editing. The button drops it.
struct ReplyChip: View {
    let text: String
    /// What you said to this quote, under it.
    var note = ""
    let cancelLabel: String
    /// Escape drops it too. One chip at a time answers Escape.
    var escapes = true
    /// Clicking the chip changes what you said; `nil` where there's nothing to change.
    var edit: (() -> Void)?
    let cancel: () -> Void

    init(quote: QuotedMessage, escapes: Bool = true, edit: @escaping () -> Void, cancel: @escaping () -> Void) {
        text = "\(quote.author): \(quote.excerpt)"
        note = quote.reply
        cancelLabel = String(localized: "Don't reply to \(quote.author)")
        self.escapes = escapes
        self.edit = edit
        self.cancel = cancel
    }

    init(text: String, cancelLabel: String, cancel: @escaping () -> Void) {
        self.text = text
        self.cancelLabel = cancelLabel
        self.cancel = cancel
    }

    var body: some View {
        HStack(spacing: 8) {
            label
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .zoomedFont(size: 11, weight: .semibold)
                    .zoomedFrame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .touchTarget(width: 24, height: 24)
            }
            .buttonStyle(.clickable(.borderless))
            .foregroundStyle(.secondary)
            .keyboardShortcut(escapes ? .cancelAction : nil)
            .accessibilityLabel(Text(cancelLabel))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, note.isEmpty ? 0 : 6)
        .zoomedFrame(minHeight: 34)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var label: some View {
        let words = VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1, accessibility: 3)
            if !note.isEmpty {
                Text(note)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1, accessibility: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let edit {
            Button(action: edit) { words.contentShape(Rectangle()) }
                .buttonStyle(.clickable)
                .help(note.isEmpty ? "Reply to this quote" : "Change your reply")
                .accessibilityLabel(Text(note.isEmpty ? text : "\(text). Your reply: \(note)"))
                .accessibilityHint(Text(note.isEmpty ? "Replies to this quote" : "Changes your reply"))
        } else {
            words
        }
    }
}

/// The quotes waiting above the message box, oldest first. Escape drops the newest. Past four
/// they scroll, so a long list doesn't push the conversation off an iPhone's screen. Clicking one
/// opens what you said to it, to change.
struct QuoteChips: View {
    @Binding var quotes: [QuotedMessage]
    /// The quote whose reply is open, by its place in the list.
    @State private var editing: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(quotes.enumerated()), id: \.offset) { index, quote in
                    ReplyChip(quote: quote, escapes: index == quotes.count - 1) {
                        editing = index
                    } cancel: {
                        editing = nil
                        quotes.remove(at: index)
                    }
                    .popover(isPresented: isEditing(index), arrowEdge: .top) {
                        if quotes.indices.contains(index) {
                            ReplyField(excerpt: quote.excerpt, note: $quotes[index].note) { editing = nil }
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }
        }
        .thinScroller()
        .scrollBounceBehavior(.basedOnSize)
        // The newest is the one just added.
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: 168)
        .fixedSize(horizontal: false, vertical: true)
        // Chips scrolled part of the way out end in the corners the others have.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func isEditing(_ index: Int) -> Binding<Bool> {
        Binding(get: { editing == index }, set: { if !$0, editing == index { editing = nil } })
    }
}
