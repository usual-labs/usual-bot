import HermesKit
import SwiftUI

/// A message you're replying to, or words you picked from one: shown above the message box, then
/// sent as `>` quote lines before your text. In a room the reply also @mentions the author, so
/// only it answers.
struct QuotedMessage: Hashable {
    let author: String
    /// One line, for the chip above the message box.
    let excerpt: String
    /// The room member to address; `nil` in a chat with one agent.
    var mention: String?
    /// The lines sent as the quote: the excerpt, or the words you selected.
    private var quoted: [String]

    /// Part of a message you selected, kept whole and line by line: you picked those words.
    init(author: String, selection: String, mention: String? = nil) {
        self.author = author
        self.mention = mention
        quoted = selection.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let flat = quoted.joined(separator: " ")
        excerpt = flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
    }

    init(author: String, text: String, mention: String? = nil) {
        self.author = author
        self.mention = mention
        // Plain words: no attachment or `MEDIA:` lines, no Markdown marks.
        let lines = AttachmentRef.split(text).text.split(whereSeparator: \.isNewline)
            .filter {
                !$0.trimmingCharacters(in: .whitespaces).hasPrefix("MEDIA:") && !MarkdownBlock.isDeliveryMarker($0)
            }
        let joined = lines.joined(separator: " ")
        let flat =
            (try? AttributedString(
                markdown: joined, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            .map { String($0.characters) } ?? joined
        excerpt = flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
        quoted = [excerpt]
    }

    /// Its `>` lines, the author's name on the first.
    fileprivate var block: String {
        quoted.enumerated().map { index, line in index == 0 ? "> \(author): \(line)" : "> \(line)" }
            .joined(separator: "\n")
    }

    /// Splits the leading quotes off a sent message: each run of `> ` lines on one line, and the
    /// rest.
    static func split(_ text: String) -> (quotes: [String], text: String) {
        var lines = text.components(separatedBy: "\n")[...]
        var quotes: [String] = []
        while lines.first?.hasPrefix("> ") == true {
            let block = lines.prefix { $0.hasPrefix("> ") }
            quotes.append(block.map { $0.dropFirst(2) }.joined(separator: " "))
            // A blank line ends a quote; the next one, or your words, follow it.
            lines = lines.dropFirst(block.count).drop { $0.allSatisfy(\.isWhitespace) }
        }
        guard !quotes.isEmpty else { return ([], text) }
        return (quotes, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension [QuotedMessage] {
    /// Adds a quote after the ones waiting. The same words twice are one quote.
    mutating func add(_ quote: QuotedMessage) {
        if !contains(quote) { append(quote) }
    }

    /// Your message with the quotes in front, a blank line between them so each stays its own. In
    /// a room it addresses each quoted member once.
    func message(_ text: String) -> String {
        guard !isEmpty else { return text }
        var mentions: [String] = []
        for mention in compactMap(\.mention) where !mentions.contains(mention) { mentions.append(mention) }
        let reply = (mentions.map { "@\($0)" } + (text.isEmpty ? [] : [text])).joined(separator: " ")
        return (map(\.block) + [reply]).joined(separator: "\n\n")
    }
}

/// What your message will be, above the message box: a message you're replying to, words you
/// added from one, or that you're editing. The button drops it.
struct ReplyChip: View {
    let text: String
    let cancelLabel: String
    /// Escape drops it too. One chip at a time answers Escape.
    var escapes = true
    let cancel: () -> Void

    init(quote: QuotedMessage, escapes: Bool = true, cancel: @escaping () -> Void) {
        text = "\(quote.author): \(quote.excerpt)"
        cancelLabel = String(localized: "Don't reply to \(quote.author)")
        self.escapes = escapes
        self.cancel = cancel
    }

    init(text: String, cancelLabel: String, cancel: @escaping () -> Void) {
        self.text = text
        self.cancelLabel = cancelLabel
        self.cancel = cancel
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1, accessibility: 3)
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
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
        .frame(minHeight: 34)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The quotes waiting above the message box, oldest first. Escape drops the newest. Past four
/// they scroll, so a long list doesn't push the conversation off an iPhone's screen.
struct QuoteChips: View {
    @Binding var quotes: [QuotedMessage]

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(quotes, id: \.self) { quote in
                    ReplyChip(quote: quote, escapes: quote == quotes.last) { quotes.removeAll { $0 == quote } }
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
}
