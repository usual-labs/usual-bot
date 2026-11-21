import SwiftUI

/// Your answer to one quote, typed beside it: Reply on selected words, and a waiting quote's chip
/// to change what you said. Return keeps it; left empty, the quote goes on its own.
struct ReplyField: View {
    let excerpt: String
    @Binding var note: String
    /// The width on the Mac, where it's a popover; `nil` fills the space it's given.
    var width: CGFloat? = 320
    let submit: () -> Void
    /// A way out where Escape isn't one (iPhone); `nil` hides it.
    var cancel: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(excerpt)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(2)
                .padding(.leading, 9)
                .overlay(alignment: .leading) { Capsule().fill(Theme.secondaryInk.opacity(0.5)).frame(width: 2) }
                .accessibilityLabel(Text("Replying to \(excerpt)"))
            HStack(spacing: 8) {
                TextField("Reply", text: $note)
                    .textFieldStyle(.plain)
                    .scaledFont(size: 14)
                    .focused($focused)
                    .onSubmit(submit)
                if let cancel {
                    Button(action: cancel) { icon("xmark") }
                        .buttonStyle(.clickable(.borderless))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Cancel"))
                }
                Button(action: submit) { icon("return") }
                    .buttonStyle(.clickable(.borderless))
                    .foregroundStyle(.secondary)
                    .help("Keep this quote and your reply (Return)")
                    .accessibilityLabel(Text("Add Reply"))
            }
        }
        .padding(12)
        .frame(width: width)
        .onAppear { focused = true }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .zoomedFont(size: 12, weight: .semibold)
            .zoomedFrame(width: 24, height: 24)
            .contentShape(Rectangle())
            .touchTarget(width: 24, height: 24)
    }

    /// Selected words on one line, as the field shows them.
    static func excerpt(of words: String) -> String {
        QuotedMessage(author: "", selection: words).excerpt
    }
}
