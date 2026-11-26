import SwiftUI

/// Your answer to one quote, typed beside it: Reply on selected words, and a waiting quote's chip
/// to change what you said. It grows to a few lines as you type. Its keys are the message box's: on
/// the Mac Return keeps it (⌘Return if that's how you send) and Shift-Return starts a line; on
/// iPhone Return starts a line and the button keeps it. Left empty, the quote goes on its own.
struct ReplyField: View {
    let excerpt: String
    @Binding var note: String
    /// The width on the Mac, where it's a popover; `nil` fills the space it's given.
    var width: CGFloat? = 320
    let submit: () -> Void
    /// A way out where Escape isn't one (iPhone); `nil` hides it.
    var cancel: (() -> Void)?
    @FocusState private var focused: Bool
    #if os(macOS)
        @State private var selection: TextSelection?
        @AppStorage(AppPreferences.commandReturnKey) private var commandReturn = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(excerpt)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(2)
                .padding(.leading, 9)
                .overlay(alignment: .leading) { Capsule().fill(Theme.secondaryInk.opacity(0.5)).frame(width: 2) }
                .accessibilityLabel(Text("Replying to \(excerpt)"))
            HStack(alignment: .bottom, spacing: 8) {
                field
                    .textFieldStyle(.plain)
                    .scaledFont(size: 14)
                    .lineLimit(1...6)
                    .focused($focused)
                    // Centred on the buttons' 24 pt while it's one line, then growing upward.
                    .padding(.vertical, 3)
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
                    .help("Keep this quote and your reply")
                    .accessibilityLabel(Text("Add Reply"))
            }
        }
        .padding(12)
        .frame(width: width)
        // Its full height whatever it's offered: a popover offers the height it opened at, and the
        // field would scroll inside one line instead of growing.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { focused = true }
    }

    #if os(macOS)
        private var field: some View {
            TextField("Reply", text: $note, selection: $selection, axis: .vertical)
                .onKeyPress(.return, phases: .down) { press in
                    if !press.modifiers.contains(.shift), !commandReturn || press.modifiers.contains(.command) {
                        submit()
                    } else {
                        insertLineBreak()
                    }
                    return .handled
                }
        }

        private func insertLineBreak() {
            guard case .selection(let range) = selection?.indices else {
                note += "\n"
                return
            }
            selection = TextSelection(insertionPoint: note.insertLineBreak(replacing: range))
        }
    #else
        private var field: some View {
            TextField("Reply", text: $note, axis: .vertical)
        }
    #endif

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
