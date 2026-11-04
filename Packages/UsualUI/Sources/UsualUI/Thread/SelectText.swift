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
    /// Shows a message's words to select from; `nil` where there's nowhere to show them.
    @Entry var selectText: ((String) -> Void)?
}

#if os(iOS)
    struct SelectingText: Identifiable {
        let id = UUID()
        let text: String
    }

    /// A message's words in a sheet, to select any part of and copy, look up or share.
    struct SelectTextSheet: View {
        let text: String
        @Environment(\.dismiss) private var dismiss
        @Environment(\.messageTextSize) private var messageSize

        var body: some View {
            NavigationStack {
                SelectableTextView(text: text, size: messageSize)
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

        func makeUIView(context: Context) -> UITextView {
            let view = UITextView()
            view.isEditable = false
            view.isSelectable = true
            view.backgroundColor = .clear
            view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
            view.adjustsFontForContentSizeCategory = true
            return view
        }

        func updateUIView(_ view: UITextView, context: Context) {
            view.text = text
            view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size))
            view.textColor = UIColor(Theme.ink)
        }
    }
#endif
