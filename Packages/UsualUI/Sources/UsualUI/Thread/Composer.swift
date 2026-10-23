import HermesKit
import SwiftUI

/// The message box under a chat. Return sends. While the agent works, a message steers it and
/// the empty box's button stops it.
struct Composer: View {
    let thread: ChatThread
    let agentName: String

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit(send)
                .padding(.leading, 14)
                .padding(.vertical, 9)
            if thread.state.isRunning, isEmpty {
                RoundButton(systemImage: "stop.fill", label: "Stop \(agentName)", action: thread.stop)
            } else {
                RoundButton(systemImage: "arrow.up", label: "Send", action: send)
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.35)
            }
        }
        .padding(5)
        .background(Theme.pane, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .onAppear { focused = true }
    }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var canSend: Bool { thread.canSend && !isEmpty }

    private var placeholder: String {
        if !thread.isAttached { return String(localized: "Reconnecting…") }
        if thread.state.isRunning { return String(localized: "Steer \(agentName) while it works") }
        return String(localized: "Message \(agentName)")
    }

    private func send() {
        guard canSend else { return }
        thread.send(text)
        text = ""
    }
}

private struct RoundButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.userBubbleInk)
                .frame(width: 36, height: 36)
                .background(Theme.userBubble, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
