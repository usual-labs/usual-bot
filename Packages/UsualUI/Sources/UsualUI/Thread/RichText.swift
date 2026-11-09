#if os(macOS)
    import AppKit
    import SwiftUI

    /// What a message's text view shows.
    enum MessageTextContent: Equatable {
        /// A run of a reply's paragraphs, headings, list items and quotes.
        case reply([MarkdownBlock], size: CGFloat)
        /// Your words as you typed them, in your bubble.
        case mine(String, size: CGFloat)
    }

    /// A message's words as one attributed string, so a single text view shows them and a drag
    /// selects across paragraphs, headings, list items and quotes. Laid out as `MarkdownView`
    /// lays out the rest: blocks 10 pt apart, 4 pt between lines, a little more room above a
    /// heading, list markers in a column of their own.
    enum RichText {
        /// Marks a quote's text, which gets a bar down its leading edge.
        static let quoteBar = NSAttributedString.Key("UsualQuoteBar")

        static func string(for content: MessageTextContent) -> NSAttributedString {
            switch content {
            case .reply(let blocks, let size): reply(blocks, size: size)
            case .mine(let text, let size): mine(text, size: size)
            }
        }

        static func reply(_ blocks: [MarkdownBlock], size: CGFloat) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let markers = blocks.compactMap { block -> String? in
                if case .listItem(let marker, _, _) = block { marker } else { nil }
            }
            // As wide as the widest marker, so "10." lines up with "9.".
            let column = max(
                14, markers.map { ceil(($0 as NSString).size(withAttributes: [.font: font(size)]).width) }.max() ?? 0)
            for (index, block) in blocks.enumerated() {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = Theme.messageLineSpacing
                paragraph.paragraphSpacing = index == blocks.count - 1 ? 0 : 10
                let piece: NSMutableAttributedString
                switch block {
                case .paragraph(let text):
                    piece = runs(text, size: size, color: ink)
                case .heading(let level, let text):
                    piece = runs(text, size: size + (level == 1 ? 5 : level == 2 ? 2 : 0), weight: .semibold, color: ink)
                    if index > 0 { paragraph.paragraphSpacingBefore = 4 }
                case .listItem(let marker, let depth, let text):
                    // "⇥•⇥words": the marker right-aligned in its column, wrapped lines under the words.
                    let indent = CGFloat(depth) * 18
                    paragraph.firstLineHeadIndent = indent
                    paragraph.headIndent = indent + column + 8
                    paragraph.tabStops = [
                        NSTextTab(textAlignment: .right, location: indent + column),
                        NSTextTab(textAlignment: .left, location: indent + column + 8),
                    ]
                    piece = NSMutableAttributedString(
                        string: "\t\(marker)\t", attributes: [.font: font(size), .foregroundColor: secondaryInk])
                    piece.append(runs(text, size: size, color: ink))
                case .quote(let text):
                    paragraph.firstLineHeadIndent = 12
                    paragraph.headIndent = 12
                    piece = runs(text, size: size, color: secondaryInk)
                    piece.addAttribute(quoteBar, value: true, range: NSRange(location: 0, length: piece.length))
                default:
                    continue
                }
                if index < blocks.count - 1 {
                    piece.append(NSAttributedString(string: "\n", attributes: [.font: font(size)]))
                }
                piece.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: piece.length))
                result.append(piece)
            }
            return result
        }

        /// Your message: shown as typed, with its addresses as links.
        static func mine(_ text: String, size: CGFloat) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = Theme.messageLineSpacing
            let result = runs(Links.detect(in: text), size: size, color: userInk)
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
            return result
        }

        /// The words as they'd be pasted: list markers followed by a space rather than tabs.
        static func plain(_ string: String) -> String {
            string.replacingOccurrences(of: "\u{2028}", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in
                    let line = line.hasPrefix("\t") ? line.dropFirst() : line
                    return line.replacingOccurrences(of: "\t", with: " ")
                }
                .joined(separator: "\n")
        }

        /// Gives bold, italic, inline code and struck-out runs their fonts, and keeps links.
        private static func runs(
            _ text: AttributedString, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor
        ) -> NSMutableAttributedString {
            let result = NSMutableAttributedString()
            for run in text.runs {
                // A line break inside a block, which mustn't start a paragraph with its spacing.
                let words = String(text[run.range].characters).replacingOccurrences(of: "\n", with: "\u{2028}")
                let inline = run.inlinePresentationIntent ?? []
                var font: NSFont
                if inline.contains(.code) {
                    font = .monospacedSystemFont(ofSize: size - 0.5, weight: .regular)
                } else {
                    font = .systemFont(ofSize: size, weight: inline.contains(.stronglyEmphasized) ? .semibold : weight)
                    if inline.contains(.emphasized) {
                        font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? font
                    }
                }
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                if inline.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if let link = run.link { attributes[.link] = link }
                result.append(NSAttributedString(string: words, attributes: attributes))
            }
            return result
        }

        private static func font(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size) }

        // The theme's colours follow the appearance when drawn.
        static var ink: NSColor { NSColor(Theme.ink) }
        static var secondaryInk: NSColor { NSColor(Theme.secondaryInk) }
        static var userInk: NSColor { NSColor(Theme.userBubbleInk) }
        static var border: NSColor { NSColor(Theme.border) }
    }
#endif
