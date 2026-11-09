import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// A message's words to select part of. The Mac selects in place; on iPhone touch and hold opens
/// the message's menu, so Select Text shows the words in a sheet, as Messages does.
enum SelectableText {
    /// The words a message shows: Markdown marks and file lines dropped, lists kept as lines.
    static func plain(_ markdown: String) -> String {
        var text = ""
        var lastWasListItem = false
        for block in MarkdownBlock.parse(markdown) {
            let line: String
            var isListItem = false
            switch block {
            case .paragraph(let words), .heading(_, let words), .quote(let words):
                line = String(words.characters)
            case .listItem(let marker, let depth, let words):
                line = String(repeating: "    ", count: depth) + "\(marker) " + String(words.characters)
                isListItem = true
            case .code(_, let code):
                line = code
            case .table(let table):
                line = table.lines.joined(separator: "\n")
            case .rule, .media, .image:
                continue
            }
            if !text.isEmpty { text += isListItem && lastWasListItem ? "\n" : "\n\n" }
            text += line
            lastWasListItem = isListItem
        }
        return text
    }
}

extension EnvironmentValues {
    /// Shows a message's words to select from, and what Add to Chat does with a selection; `nil`
    /// where there's nowhere to show them.
    @Entry var selectText: ((String, @escaping (String) -> Void) -> Void)?
}

#if os(iOS)
    struct SelectingText: Identifiable {
        let id = UUID()
        let text: String
        /// Quotes the selected words in your next message.
        let quote: (String) -> Void
    }

    /// A message's words in a sheet, to select any part of and copy, look up, share or add to the
    /// chat as a quote.
    struct SelectTextSheet: View {
        let text: String
        let quote: (String) -> Void
        @Environment(\.dismiss) private var dismiss
        @Environment(\.messageTextSize) private var messageSize

        var body: some View {
            NavigationStack {
                SelectableTextView(text: text, size: messageSize) { words in
                    dismiss()
                    quote(words)
                }
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .tint(Theme.ink)
            .presentationDetents([.medium, .large])
        }
    }

    /// SwiftUI's `Text` on iPhone selects only all of itself; `UITextView` selects any part.
    private struct SelectableTextView: UIViewRepresentable {
        let text: String
        let size: CGFloat
        let quote: (String) -> Void

        func makeUIView(context: Context) -> UITextView {
            let view = UITextView()
            view.isEditable = false
            view.isSelectable = true
            view.backgroundColor = .clear
            view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
            view.adjustsFontForContentSizeCategory = true
            view.delegate = context.coordinator
            return view
        }

        func updateUIView(_ view: UITextView, context: Context) {
            context.coordinator.quote = quote
            guard view.text != text else { return }
            let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size))
            let words = NSMutableAttributedString(
                string: text, attributes: [.font: font, .foregroundColor: UIColor(Theme.ink)])
            let linked = Links.detect(in: text)
            for (url, range) in linked.runs[\.link] {
                guard let url else { continue }
                words.addAttribute(.link, value: url, range: NSRange(range, in: linked))
            }
            view.attributedText = words
            view.linkTextAttributes = [
                .foregroundColor: UIColor.link, .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        }

        func makeCoordinator() -> Coordinator { Coordinator(quote: quote) }

        final class Coordinator: NSObject, UITextViewDelegate {
            var quote: (String) -> Void

            init(quote: @escaping (String) -> Void) { self.quote = quote }

            /// Add to Chat first in the selection's menu, ahead of Copy, Look Up and Share.
            func textView(
                _ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]
            ) -> UIMenu? {
                guard range.length > 0, let words = (textView.text as NSString?)?.substring(with: range) else {
                    return UIMenu(children: suggestedActions)
                }
                let add = UIAction(title: String(localized: "Add to Chat"), image: UIImage(systemName: "text.quote")) {
                    [quote] _ in quote(words)
                }
                return UIMenu(children: [add] + suggestedActions)
            }
        }
    }
#endif
