import HermesKit
import SwiftUI

/// The message box under a chat with one agent. Return sends. While the agent works, a message
/// steers it and the empty box's button stops it.
struct Composer: View {
    let thread: ChatThread
    let agentName: String

    var body: some View {
        MessageBox(
            placeholder: placeholder, isRunning: thread.state.isRunning, canSend: thread.canSend,
            stopLabel: String(localized: "Stop \(agentName)"), send: thread.send, stop: thread.stop)
    }

    private var placeholder: String {
        if !thread.isAttached { return String(localized: "Reconnecting…") }
        if thread.state.isRunning { return String(localized: "Steer \(agentName) while it works") }
        return String(localized: "Message \(agentName)")
    }
}

/// Someone you can @mention in a room.
struct Mention: Identifiable, Equatable {
    /// The handle the gateway routes by.
    let id: String
    let name: String
    let contact: Contact
}

/// The rounded message box shared by chats and rooms: a growing text field, Send, and Stop while
/// something runs and the box is empty. In rooms, typing `@` suggests members to mention.
struct MessageBox: View {
    let placeholder: String
    let isRunning: Bool
    let canSend: Bool
    let stopLabel: String
    var mentions: [Mention] = []
    let send: (String) -> Void
    let stop: () -> Void

    @State private var text = ""
    /// Where the cursor is, to put a line break there.
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions) { mention in
                            Button {
                                complete(with: mention)
                            } label: {
                                HStack(spacing: 6) {
                                    AgentAvatar(contact: mention.contact, size: 22)
                                    Text(mention.name).font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                                    Text("@\(mention.id)").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryInk)
                                }
                                .padding(.leading, 4)
                                .padding(.trailing, 10)
                                .frame(minHeight: 32)
                                .background(Theme.pane, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.border))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Mention \(mention.name)"))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, selection: $selection, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...8)
                    .focused($focused)
                    // Return sends; Shift-Return starts a new line.
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.shift) else { return .ignored }
                        insertLineBreak()
                        return .handled
                    }
                    .onSubmit(submit)
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
                if isRunning, isEmpty {
                    RoundButton(systemImage: "stop.fill", label: stopLabel, action: stop)
                } else {
                    RoundButton(systemImage: "arrow.up", label: String(localized: "Send"), action: submit)
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.35)
                }
            }
            // 36 pt tall on one line, like the name pill above.
            .padding(4)
            .floatingSurface(in: RoundedRectangle(cornerRadius: 18))
        }
        .onAppear { focused = true }
    }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func insertLineBreak() {
        guard case .selection(let range) = selection?.indices else {
            text += "\n"
            return
        }
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        text.replaceSubrange(range, with: "\n")
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset + 1))
    }

    private var canSubmit: Bool { canSend && !isEmpty }

    private func submit() {
        guard canSubmit else { return }
        send(text)
        text = ""
    }

    /// The word being typed, when it starts with `@`.
    private var mentionQuery: String? {
        guard !mentions.isEmpty, let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
            last.hasPrefix("@")
        else { return nil }
        return String(last.dropFirst()).lowercased()
    }

    private var suggestions: [Mention] {
        guard let query = mentionQuery else { return [] }
        if query.isEmpty { return mentions }
        return mentions.filter { $0.id.lowercased().hasPrefix(query) || $0.name.lowercased().hasPrefix(query) }
    }

    private func complete(with mention: Mention) {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if words.isEmpty { words = [""] }
        words[words.count - 1] = "@\(mention.id)"
        text = words.joined(separator: " ") + " "
        focused = true
    }
}

private struct RoundButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.primaryInk)
                .frame(width: 28, height: 28)
                .background(Theme.primary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
