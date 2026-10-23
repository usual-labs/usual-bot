import HermesKit
import SwiftUI

/// The message box under a chat with one agent. Return sends. While the agent works, a message
/// steers it and the empty box's button stops it. Files can go with a message between turns.
struct Composer: View {
    let thread: ChatThread
    let agentName: String
    @Binding var attachments: [Attachment]
    @Binding var replyTo: QuotedMessage?

    var body: some View {
        MessageBox(
            placeholder: placeholder, isRunning: thread.state.isRunning, canSend: thread.canSend,
            stopLabel: String(localized: "Stop \(agentName)"),
            attaching: AttachmentSending(
                attachments: $attachments, canSend: thread.canSendAttachments, isUploading: thread.isUploading,
                send: thread.send(_:attachments:)),
            replyTo: $replyTo,
            commands: SlashCommands(
                list: thread.commands, load: { Task { await thread.loadCommands() } },
                prefill: Binding(get: { thread.prefill }, set: { thread.prefill = $0 })),
            send: thread.send, stop: thread.stop)
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
    /// Chats only: files waiting to go with the message.
    var attaching: AttachmentSending?
    /// The message you're replying to, quoted in front of yours.
    var replyTo: Binding<QuotedMessage?>?
    /// Chats only: skills and commands to offer after `/`.
    var commands: SlashCommands?
    let send: (String) -> Void
    let stop: () -> Void

    @State private var text = ""
    /// The menu row Return picks.
    @State private var highlighted = 0
    /// When Return last picked from the menu: the field may still submit for that same press.
    @State private var pickedAt: Date?
    /// Escape closes the menu until you type again.
    @State private var dismissedText: String?
    /// Where the cursor is, to put a line break there.
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @Environment(\.conversationTaps) private var conversationTaps
    @State private var dictation = Dictation()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !menu.isEmpty {
                SuggestionMenu(
                    items: menu, highlighted: min(highlighted, menu.count - 1), highlight: { highlighted = $0 },
                    pick: pick)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let quote = replyTo?.wrappedValue {
                    ReplyChip(quote: quote) { replyTo?.wrappedValue = nil }
                }
                if let attaching, !attaching.attachments.isEmpty {
                    AttachmentChips(attachments: attaching.$attachments)
                    if isRunning {
                        Text("You can send these when the reply ends.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryInk)
                            .padding(.horizontal, 8)
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    if let attaching {
                        AttachButton { attaching.attachments.append(contentsOf: $0) }
                    }
                    field
                    sendButton
                }
                switch dictation.state {
                case .denied(let message):
                    DictationProblem(message: message, showsSettings: true, dismiss: dictation.dismissProblem)
                case .failed(let message):
                    DictationProblem(message: message, showsSettings: false, dismiss: dictation.dismissProblem)
                default:
                    EmptyView()
                }
            }
            // 36 pt tall on one line, like the name pill above.
            .padding(4)
            .floatingSurface(in: RoundedRectangle(cornerRadius: 18))
        }
        .onAppear { focused = true }
        .onDisappear { dictation.stop() }
        // The menu reads the gateway's list each time it opens.
        .onChange(of: slashQuery != nil) { _, open in if open { commands?.load() } }
        // Clicking or tapping the conversation closes the menu, like Escape.
        .onChange(of: conversationTaps) { closeMenu() }
        .onChange(of: menuText) { _, text in
            highlighted = 0
            if text != dismissedText { dismissedText = nil }
        }
        .onChange(of: commands?.prefill) { _, prefill in
            guard let prefill else { return }
            text = prefill
            commands?.prefill = nil
            focused = true
        }
    }

    /// The text the menus read. On iPhone a hardware Return can add its newline before the field
    /// submits; the menu ignores it so that Return still picks the highlighted row.
    private var menuText: String {
        var text = text
        while text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    /// What's typed after a leading `/`, while it's still one word.
    private var slashQuery: String? {
        guard commands != nil, menuText.hasPrefix("/"), !menuText.contains(where: \.isWhitespace) else { return nil }
        return String(menuText.dropFirst())
    }

    private var commandSuggestions: [SlashCommand] {
        guard let commands, let query = slashQuery else { return [] }
        let matches = commands.matching(query)
        // Typed in full: nothing left to pick.
        return matches.count == 1 && matches[0].name == menuText ? [] : matches
    }

    private func complete(with command: SlashCommand) {
        text = command.name + " "
        focused = true
    }

    /// The `/` menu's matches, else the `@` menu's.
    private var menu: [Suggestion] {
        guard menuText != dismissedText else { return [] }
        if !commandSuggestions.isEmpty { return commandSuggestions.map(Suggestion.command) }
        return suggestions.map(Suggestion.mention)
    }

    /// Hides the menu until you type again.
    private func closeMenu() {
        if !menu.isEmpty { dismissedText = menuText }
    }

    private func pick(_ item: Suggestion) {
        switch item {
        case .command(let command): complete(with: command)
        case .mention(let mention): complete(with: mention)
        }
    }

    /// Up and Down move through the menu, wrapping at the ends; without a menu the keys move the cursor.
    private func moveHighlight(by step: Int) -> KeyPress.Result {
        guard !menu.isEmpty else { return .ignored }
        highlighted = (min(highlighted, menu.count - 1) + step + menu.count) % menu.count
        return .handled
    }

    private func pickHighlighted() -> KeyPress.Result {
        guard !menu.isEmpty else { return .ignored }
        pick(menu[min(highlighted, menu.count - 1)])
        pickedAt = .now
        return .handled
    }

    private var field: some View {
        TextField(
            replyTo?.wrappedValue == nil ? placeholder : String(localized: "Reply…"), text: $text,
            selection: $selection, axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .lineLimit(1...8)
        .focused($focused)
        // Return sends, or picks from an open menu; Shift-Return starts a new line.
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.shift) else { return pickHighlighted() }
            insertLineBreak()
            return .handled
        }
        .onKeyPress(.downArrow) { moveHighlight(by: 1) }
        .onKeyPress(.upArrow) { moveHighlight(by: -1) }
        .onKeyPress(.tab) { pickHighlighted() }
        .onKeyPress(.escape) {
            guard !menu.isEmpty else { return .ignored }
            closeMenu()
            return .handled
        }
        .onSubmit(submit)
        #if os(macOS)
            // Pasted files and images become attachments; text pastes as usual.
            .onPasteCommand(of: attaching == nil ? [] : [.fileURL, .image]) { providers in
                Task { attaching?.attachments.append(contentsOf: await AttachmentLoader.load(providers)) }
            }
        #endif
        .padding(.leading, attaching == nil ? 12 : 0)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var sendButton: some View {
        if attaching?.isUploading == true {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
                .accessibilityLabel(Text("Uploading"))
        } else if isRunning, isEmpty, !hasAttachments, !dictation.isListening {
            RoundButton(systemImage: "stop.fill", label: stopLabel, action: stop)
        } else if dictation.isListening || (isEmpty && !hasAttachments) {
            // An empty box offers the mic, as Messages and Grok Bot do; Send takes over once
            // there's something to send.
            MicButton(dictation: dictation) {
                dictation.start(after: text) { text = $0 }
                focused = true
            }
        } else {
            RoundButton(systemImage: "arrow.up", label: String(localized: "Send"), action: submit)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.35)
        }
    }

    private var hasAttachments: Bool { attaching?.attachments.isEmpty == false }

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

    private var canSubmit: Bool {
        if let attaching, !attaching.attachments.isEmpty { return attaching.canSend }
        return canSend && !isEmpty
    }

    private func submit() {
        // Return with a menu open picks its row. On iPhone the field submits for the same press
        // after the key handler picked, which must not send the command you just picked.
        if let pickedAt, Date.now.timeIntervalSince(pickedAt) < 0.3 {
            self.pickedAt = nil
            return
        }
        if pickHighlighted() == .handled { return }
        guard canSubmit else { return }
        // Sending ends dictation; words still arriving would land in the next message.
        dictation.stop()
        let quote = replyTo?.wrappedValue
        if let attaching, !attaching.attachments.isEmpty {
            // Text and files leave together once every file is up; a failure keeps both here.
            let draft = text
            let files = attaching.attachments
            Task {
                guard await attaching.send(quote?.message(draft) ?? draft, files) else { return }
                if text == draft { text = "" }
                if replyTo?.wrappedValue == quote { replyTo?.wrappedValue = nil }
                attaching.attachments.removeAll { sent in files.contains { $0.id == sent.id } }
            }
            return
        }
        send(quote?.message(text) ?? text)
        text = ""
        replyTo?.wrappedValue = nil
    }

    /// The word being typed, when it starts with `@`.
    private var mentionQuery: String? {
        guard !mentions.isEmpty, let last = menuText.split(separator: " ", omittingEmptySubsequences: false).last,
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
        var words = menuText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
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
