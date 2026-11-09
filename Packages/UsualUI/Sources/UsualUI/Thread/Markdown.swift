import Foundation
import SwiftUI

/// A block of a Markdown reply, rendered as its own view.
enum MarkdownBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    /// `marker` is "•" or "3."; `depth` starts at 0.
    case listItem(marker: String, depth: Int, AttributedString)
    case quote(AttributedString)
    case code(language: String?, String)
    case rule
    /// A file on the gateway the agent delivered with a `MEDIA:/path` line, or a Markdown image
    /// with a local path. `voice`: the reply asked for its audio as a voice message.
    case media(path: String, voice: Bool = false)
    /// A Markdown image from the web.
    case image(URL, alt: String)
    case table(MarkdownTable)

    /// `parse`, remembered: a chat's views are made again on every change to it (each word of a
    /// reply being written), and parsing every message each time made long chats slow.
    @MainActor static func blocks(of markdown: String) -> [MarkdownBlock] {
        if let blocks = parsed[markdown] { return blocks }
        let blocks = parse(markdown)
        if parsed.count >= 500 { parsed.removeAll(keepingCapacity: true) }
        parsed[markdown] = blocks
        return blocks
    }

    @MainActor private static var parsed: [String: [MarkdownBlock]] = [:]

    /// Splits a reply into blocks: `MEDIA:` lines (Hermes's line-level file delivery) become media
    /// blocks, and everything between them is Markdown.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        // "\r\n" is one Character in Swift, so splitting on "\n" alone wouldn't find its lines.
        let markdown = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var blocks: [MarkdownBlock] = []
        var pending: [Substring] = []
        var inFence = false
        // Hermes's delivery markers (`[[audio_as_voice]]` from its TTS tool) aren't for reading;
        // the gateway strips them for its messaging platforms too.
        let voice = markdown.contains(voiceMarker)
        func flush() {
            if !pending.isEmpty { blocks += parseMarkdown(keepingLineBreaks(pending)) }
            pending = []
        }
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            if !inFence, isDeliveryMarker(trimmed) {
                continue
            } else if !inFence, trimmed.hasPrefix("MEDIA:"),
                let path = mediaPath(trimmed.dropFirst("MEDIA:".count))
            {
                flush()
                blocks.append(.media(path: path, voice: voice))
            } else if !inFence, let path = mediaPath(Substring(trimmed)), imagePaths(in: path) == [path] {
                // A line that's only the path to an image: agents outside the desktop app name
                // the files they make that way.
                flush()
                blocks.append(.media(path: path))
            } else {
                pending.append(line)
            }
        }
        flush()
        return blocks
    }

    static let voiceMarker = "[[audio_as_voice]]"

    /// A line that only tells Hermes how to deliver files, which nobody reads.
    static func isDeliveryMarker(_ line: some StringProtocol) -> Bool {
        let line = line.trimmingCharacters(in: .whitespaces)
        return line == voiceMarker || line == "[[as_document]]"
    }

    /// The path in a `MEDIA:` line, unquoted; `nil` when there is none.
    private static func mediaPath(_ value: Substring) -> String? {
        var path = value.trimmingCharacters(in: .whitespaces)
        if let first = path.first, "`\"'".contains(first), path.count > 1, path.last == first {
            path = String(path.dropFirst().dropLast())
        }
        return path.isEmpty ? nil : path
    }

    /// Splits Markdown into blocks using Foundation's parser. Inline styling (bold, italic, links,
    /// inline code) stays in each block's `AttributedString` as presentation intents, which
    /// `MarkdownView` turns into fonts. A table's cells gather into one block; images become
    /// blocks of their own after their paragraph.
    private static func parseMarkdown(_ markdown: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let document = try? AttributedString(markdown: markdown, options: options) else {
            return [.paragraph(AttributedString(markdown))]
        }
        var blocks: [MarkdownBlock] = []
        var lastTable: (id: Int, row: Int?)?
        for (intent, range) in document.runs[\.presentationIntent] {
            let kinds = intent?.components.map(\.kind) ?? []
            let isCode = kinds.contains { if case .codeBlock = $0 { true } else { false } }
            // Addresses typed out bare are links too, except in code.
            let text = isCode ? AttributedString(document[range]) : Links.detect(in: AttributedString(document[range]))
            guard let intent else {
                blocks.append(.paragraph(text))
                continue
            }
            if let cell = tableCell(intent) {
                if lastTable?.id == cell.table, case .table(var table) = blocks.last {
                    table.add(text, row: cell.row, newRow: cell.row != lastTable?.row, column: cell.column)
                    blocks[blocks.count - 1] = .table(table)
                } else {
                    var table = MarkdownTable(cell.columns)
                    table.add(text, row: cell.row, newRow: true, column: cell.column)
                    blocks.append(.table(table))
                }
                lastTable = (cell.table, cell.row)
                continue
            }
            lastTable = nil
            if let language = kinds.lazy.compactMap({ kind -> String?? in
                if case .codeBlock(let hint) = kind { return .some(hint) }
                return nil
            }).first {
                var code = String(text.characters)
                while code.hasSuffix("\n") { code.removeLast() }
                blocks.append(.code(language: language?.nonEmpty, code))
            } else if kinds.contains(.thematicBreak) {
                blocks.append(.rule)
            } else if let level = kinds.lazy.compactMap({ kind -> Int? in
                if case .header(let level) = kind { return level }
                return nil
            }).first {
                blocks.append(.heading(level: level, text))
            } else if let item = listItem(in: intent) {
                blocks.append(.listItem(marker: item.marker, depth: item.depth, text))
                blocks += imagePaths(in: String(text.characters)).map { .media(path: $0) }
            } else if kinds.contains(.blockQuote) {
                blocks.append(.quote(text))
            } else {
                let (rest, images) = splitImages(text)
                if !rest.characters.allSatisfy(\.isWhitespace) { blocks.append(.paragraph(rest)) }
                blocks += images
                // Image paths named in the text show under it.
                blocks += imagePaths(in: String(rest.characters)).map { .media(path: $0) }
            }
        }
        return blocks
    }

    /// Absolute paths to image files in `text`, in order, each once: `/home/…/chart.png`.
    static func imagePaths(in text: String) -> [String] {
        guard let regex = imagePathPattern else { return [] }
        var seen: Set<String> = []
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let path = String(text[range])
            return seen.insert(path).inserted ? path : nil
        }
    }

    private static let imagePathPattern = try? NSRegularExpression(
        pattern: #"(?<![\w.~/:])/(?!/)[^\s`'"<>()\[\]]+\.(?:png|jpe?g|gif|webp|bmp|heic)\b"#,
        options: .caseInsensitive)

    /// Takes the images out of a paragraph: web images load directly, local paths from the gateway.
    private static func splitImages(_ text: AttributedString) -> (AttributedString, [MarkdownBlock]) {
        var rest = text
        var images: [MarkdownBlock] = []
        for (url, range) in text.runs[\.imageURL].reversed() {
            guard let url else { continue }
            let alt = String(text[range].characters)
            if url.scheme == "http" || url.scheme == "https" {
                images.insert(.image(url, alt: alt), at: 0)
            } else if url.isFileURL || url.scheme == nil, url.path.hasPrefix("/") {
                images.insert(.media(path: url.path), at: 0)
            } else {
                continue
            }
            rest.removeSubrange(range)
        }
        return (rest, images)
    }

    /// Components run from the innermost block outwards: a list item's own list follows it.
    private static func listItem(in intent: PresentationIntent) -> (marker: String, depth: Int)? {
        let components = intent.components
        guard let index = components.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
            case .listItem(let ordinal) = components[index].kind
        else { return nil }
        let lists = components.filter { $0.kind == .orderedList || $0.kind == .unorderedList }
        let ordered =
            components[(index + 1)...].first { $0.kind == .orderedList || $0.kind == .unorderedList }?
            .kind == .orderedList
        return (ordered ? "\(ordinal)." : "•", max(lists.count - 1, 0))
    }

    /// Where a run of a table sits: its table, its row (`nil` for the header) and its column.
    private static func tableCell(_ intent: PresentationIntent) -> (
        table: Int, columns: [PresentationIntent.TableColumn], row: Int?, column: Int
    )? {
        var column: Int?
        var row: Int?
        for component in intent.components {
            switch component.kind {
            case .tableCell(let index): column = index
            case .tableRow: row = component.identity
            case .table(let columns):
                guard let column else { return nil }
                return (component.identity, columns, row, column)
            default: continue
            }
        }
        return nil
    }
}

/// Renders a Markdown reply, block by block.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    @Environment(\.messageTextSize) private var messageSize

    /// A reply still being written changes with each word, so it isn't remembered.
    init(_ markdown: String, isBeingWritten: Bool = false) {
        blocks = isBeingWritten ? MarkdownBlock.parse(markdown) : MarkdownBlock.blocks(of: markdown)
    }

    var body: some View {
        // As wide as its text, for a bubble around it.
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let text, let headed):
                    Text(text).fixedSize(horizontal: false, vertical: true).padding(.top, headed ? 4 : 0)
                        .tint(Theme.link)
                case .flow(let blocks, let headed):
                    #if os(macOS)
                        MessageText(content: .reply(blocks, size: messageSize)).padding(.top, headed ? 4 : 0)
                    #endif
                case .block(let block): view(for: block)
                }
            }
        }
        .messageFont()
        .foregroundStyle(Theme.ink)
        .textSelection(.enabled)
    }

    /// What the reply draws. On the Mac, paragraphs, headings, list items and quotes in a row are
    /// one AppKit text view (`MessageText`), so a drag selects across them all. On iPhone, where
    /// Select Text shows the words in a sheet, paragraphs and headings in a row are one `Text`.
    /// Either way there's one selectable view where there was one per paragraph: the Mac checked
    /// each on every move of the pointer, which slowed long chats down.
    private enum Part {
        /// `headed`: it starts with a heading, which gets a little more room above it.
        case text(AttributedString, headed: Bool)
        case flow([MarkdownBlock], headed: Bool)
        case block(MarkdownBlock)
    }

    private var parts: [Part] {
        #if os(macOS)
            var parts: [Part] = []
            for block in blocks {
                switch block {
                case .paragraph, .heading, .listItem, .quote:
                    if case .flow(let run, let headed) = parts.last {
                        parts[parts.count - 1] = .flow(run + [block], headed: headed)
                    } else {
                        let headed = if case .heading = block { true } else { false }
                        parts.append(.flow([block], headed: headed))
                    }
                default:
                    parts.append(.block(block))
                }
            }
            return parts
        #else
            return textParts
        #endif
    }

    private var textParts: [Part] {
        var parts: [Part] = []
        for block in blocks {
            let piece: AttributedString
            // A blank line in a tiny font: Text ignores paragraph spacing. With the message font's
            // 4 pt line spacing on both line breaks, 2 pt makes the 10 pt the stack puts between
            // blocks, and 5 pt the extra room above a heading.
            let gap: CGFloat
            switch block {
            case .paragraph(let text):
                piece = styled(text)
                gap = 2
            case .heading(let level, let text):
                let size = headingSize(level)
                var heading = text
                heading.font = .system(size: size, weight: .semibold)
                piece = styled(heading, size: size, weight: .semibold)
                gap = 5
            default:
                parts.append(.block(block))
                continue
            }
            if case .text(let previous, let headed) = parts.last {
                var blank = AttributedString("\n\n")
                blank.font = .system(size: gap)
                parts[parts.count - 1] = .text(previous + blank + piece, headed: headed)
            } else {
                parts.append(.text(piece, headed: gap == 5))
            }
        }
        return parts
    }

    private func headingSize(_ level: Int) -> CGFloat {
        messageSize + (level == 1 ? 5 : level == 2 ? 2 : 0)
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(styled(text)).fixedSize(horizontal: false, vertical: true).tint(Theme.link)
        case .heading(let level, let text):
            let size = headingSize(level)
            Text(styled(text, size: size, weight: .semibold))
                .font(.system(size: size, weight: .semibold))
                .padding(.top, 4)
                .tint(Theme.link)
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).foregroundStyle(Theme.secondaryInk).frame(minWidth: 14, alignment: .trailing)
                Text(styled(text)).fixedSize(horizontal: false, vertical: true).tint(Theme.link)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let text):
            Text(styled(text))
                .foregroundStyle(Theme.secondaryInk)
                .tint(Theme.link)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(Theme.border).frame(width: 3) }
        case .code(let language, let code):
            CodeBlock(language: language, code: code)
        case .rule:
            Divider().overlay(Theme.border)
        case .media(let path, let voice):
            MediaView(path: path, voice: voice)
        case .image(let url, let alt):
            ReplyImage(source: .web(url), name: alt.isEmpty ? url.lastPathComponent : alt)
        case .table(let table):
            MarkdownTableView(table: table) { styled($0, weight: $1) }
                .tint(Theme.link)
        }
    }

    /// Gives bold, italic and inline-code runs their own fonts, and underlines links (which take
    /// the tint's colour). Text draws Markdown's bold and italic only while no explicit font is
    /// set, and the chat always sets one.
    private func styled(
        _ text: AttributedString, size: CGFloat? = nil, weight: Font.Weight = .regular
    ) -> AttributedString {
        let size = size ?? messageSize
        var text = text.underliningLinks()
        for (inline, range) in text.runs[\.inlinePresentationIntent] {
            guard let inline, !inline.isEmpty else { continue }
            if inline.contains(.code) {
                // Monospaced letters run large beside the text's, so they're set a step smaller.
                text[range].font = .system(size: size * 0.9, design: .monospaced)
                text[range].foregroundColor = Theme.codeInk
                text[range].backgroundColor = Theme.codeChip
                continue
            }
            var font = Font.system(size: size, weight: inline.contains(.stronglyEmphasized) ? .semibold : weight)
            if inline.contains(.emphasized) { font = font.italic() }
            text[range].font = font
        }
        return text
    }
}

/// A fenced code block with a language label and a copy button.
struct CodeBlock: View {
    let language: String?
    let code: String
    @Environment(\.messageTextSize) private var messageSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.secondaryInk)
                Spacer()
                Button("Copy") { Clipboard.copy(code) }
                    .buttonStyle(.clickable)
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(minHeight: 28)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .scaledFont(size: 13 + messageSize - Theme.messageSize, design: .monospaced)
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 12))
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
