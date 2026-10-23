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
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...8)
                    .focused($focused)
                    .onSubmit(submit)
                    .padding(.leading, 14)
                    .padding(.vertical, 9)
                if isRunning, isEmpty {
                    RoundButton(systemImage: "stop.fill", label: stopLabel, action: stop)
                } else {
                    RoundButton(systemImage: "arrow.up", label: String(localized: "Send"), action: submit)
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.35)
                }
            }
            .padding(5)
            .floatingSurface(in: RoundedRectangle(cornerRadius: 24))
        }
        .onAppear { focused = true }
    }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.primaryInk)
                .frame(width: 36, height: 36)
                .background(Theme.primary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
