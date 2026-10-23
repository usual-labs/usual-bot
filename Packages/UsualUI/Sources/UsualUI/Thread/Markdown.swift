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

    /// Splits Markdown into blocks using Foundation's parser. Inline styling (bold, italic, links,
    /// inline code) stays in each block's `AttributedString` as presentation intents, which
    /// `MarkdownView` turns into fonts. Table cells of one row join into a line.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let document = try? AttributedString(markdown: markdown, options: options) else {
            return [.paragraph(AttributedString(markdown))]
        }
        var blocks: [MarkdownBlock] = []
        var lastTableRow: Int?
        for (intent, range) in document.runs[\.presentationIntent] {
            let text = AttributedString(document[range])
            guard let intent else {
                blocks.append(.paragraph(text))
                continue
            }
            let kinds = intent.components.map(\.kind)
            if let rowID = tableRowIdentity(intent) {
                if rowID == lastTableRow, case .paragraph(let previous) = blocks.last {
                    blocks[blocks.count - 1] = .paragraph(previous + AttributedString("  ·  ") + text)
                } else {
                    blocks.append(.paragraph(text))
                }
                lastTableRow = rowID
                continue
            }
            lastTableRow = nil
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
            } else if kinds.contains(.blockQuote) {
                blocks.append(.quote(text))
            } else {
                blocks.append(.paragraph(text))
            }
        }
        return blocks
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

    private static func tableRowIdentity(_ intent: PresentationIntent) -> Int? {
        for component in intent.components {
            switch component.kind {
            case .tableRow, .tableHeaderRow: return component.identity
            default: continue
            }
        }
        return nil
    }
}

/// Renders a Markdown reply, block by block.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    @Environment(\.colorScheme) private var colorScheme

    init(_ markdown: String) {
        blocks = MarkdownBlock.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .messageFont()
        .foregroundStyle(Theme.ink)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(styled(text)).fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            let size = Theme.messageSize + (level == 1 ? 5 : level == 2 ? 2 : 0)
            Text(styled(text, size: size, weight: .semibold))
                .font(.system(size: size, weight: .semibold))
                .padding(.top, 4)
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).foregroundStyle(Theme.secondaryInk).frame(minWidth: 14, alignment: .trailing)
                Text(styled(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let text):
            Text(styled(text))
                .foregroundStyle(Theme.secondaryInk)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(Theme.border).frame(width: 3) }
        case .code(let language, let code):
            CodeBlock(language: language, code: code)
        case .rule:
            Divider().overlay(Theme.border)
        }
    }

    /// Gives bold, italic and inline-code runs their own fonts. Text draws Markdown's bold and
    /// italic only while no explicit font is set, and the chat always sets one.
    private func styled(
        _ text: AttributedString, size: CGFloat = Theme.messageSize, weight: Font.Weight? = nil
    ) -> AttributedString {
        let weight = weight ?? Theme.messageWeight(colorScheme)
        var text = text
        for (inline, range) in text.runs[\.inlinePresentationIntent] {
            guard let inline, !inline.isEmpty else { continue }
            if inline.contains(.code) {
                text[range].font = .system(size: size - 0.5, design: .monospaced)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                Spacer()
                Button("Copy") { Clipboard.copy(code) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(minHeight: 28)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
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
