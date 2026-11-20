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
            case .rule, .media, .image, .widget:
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
    /// Shows a message's words to select from, and what Reply does with a selection and what you
    /// said to it; `nil` where there's nowhere to show them.
    @Entry var selectText: ((String, @escaping (_ words: String, _ reply: String) -> Void) -> Void)?
}

#if os(iOS)
    struct SelectingText: Identifiable {
        let id = UUID()
        let text: String
        /// Quotes the selected words in your next message, with your reply under them.
        let quote: (String, String) -> Void
    }

    /// A message's words in a sheet, to select any part of and copy, look up, share or reply to.
    /// It stays open for the next part; the quotes reach the message box as it closes, so the
    /// keyboard comes up there and not under the sheet.
    struct SelectTextSheet: View {
        let text: String
        let quote: (String, String) -> Void
        @Environment(\.dismiss) private var dismiss
        @Environment(\.messageTextSize) private var messageSize
        /// The words whose Reply field is open.
        @State private var replying: String?
        @State private var reply = ""
        /// Kept so far, with what you said to each.
        @State private var kept: [(words: String, reply: String)] = []

        var body: some View {
            NavigationStack {
                SelectableTextView(text: text, size: messageSize) { words in
                    reply = ""
                    replying = words
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .tint(Theme.ink)
            .presentationDetents([.medium, .large])
            .onDisappear {
                for quote in kept { self.quote(quote.words, quote.reply) }
            }
        }

        @ViewBuilder private var bottomBar: some View {
            if let replying {
                ReplyField(excerpt: ReplyField.excerpt(of: replying), note: $reply, width: nil) {
                    kept.append((replying, reply))
                    self.replying = nil
                } cancel: {
                    self.replying = nil
                }
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            } else if !kept.isEmpty {
                Text("^[\(kept.count) quote](inflect: true) will go in your message.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
        }
    }

    /// SwiftUI's `Text` on iPhone selects only all of itself; `UITextView` selects any part.
    private struct SelectableTextView: UIViewRepresentable {
        let text: String
        let size: CGFloat
        /// Opens the Reply field for the selected words.
        let reply: (String) -> Void

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
            context.coordinator.reply = reply
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

        func makeCoordinator() -> Coordinator { Coordinator(reply: reply) }

        final class Coordinator: NSObject, UITextViewDelegate {
            var reply: (String) -> Void

            init(reply: @escaping (String) -> Void) { self.reply = reply }

            /// Reply first in the selection's menu, ahead of Copy, Look Up and Share. It lets go of
            /// the selection: the field shows the words, and the next part can be picked.
            func textView(
                _ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]
            ) -> UIMenu? {
                guard range.length > 0, let words = (textView.text as NSString?)?.substring(with: range) else {
                    return UIMenu(children: suggestedActions)
                }
                let add = UIAction(
                    title: String(localized: "Reply"), image: UIImage(systemName: "arrowshape.turn.up.left")
                ) { [reply, weak textView] _ in
                    textView?.selectedTextRange = nil
                    reply(words)
                }
                return UIMenu(children: [add] + suggestedActions)
            }
        }
    }
#endif
