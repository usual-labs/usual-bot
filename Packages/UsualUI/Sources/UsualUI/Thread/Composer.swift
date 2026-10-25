import HermesKit
import SwiftUI

/// The message box under a chat with one agent, with its model and thinking choices (menus under
/// the box on the Mac, controls inside it while you type on iPhone). Return sends. While the agent
/// works, a message steers it and the empty box's button stops it. Files can go with a message
/// between turns.
struct Composer: View {
    let thread: ChatThread
    let agentName: String
    /// The agent's default model, for the model menu's Make Default.
    var agentDefault: AgentDetails?
    @Binding var attachments: [Attachment]
    @Binding var replyTo: QuotedMessage?
    /// You're rewriting your last message: Send replaces it.
    @Binding var editing: Bool
    /// A call holds the microphone: no dictation or second call meanwhile.
    var inCall = false
    var startCall: (() -> Void)?

    var body: some View {
        // Background tasks and side answers float above the box; on the Mac the model and thinking
        // menus sit under it, on the right.
        VStack(alignment: .trailing, spacing: ModelControls.gap) {
            if !thread.backgroundTasks.isEmpty {
                BackgroundTasksBar(tasks: thread.backgroundTasks).padding(.bottom, 6)
            }
            ForEach(thread.sideQuestions) { question in
                SideQuestionCard(question: question) { thread.dismiss(question) }
                    .padding(.bottom, 6)
            }
            box
            #if os(macOS)
                ModelControls(thread: thread, agentName: agentName, agentDefault: agentDefault)
            #endif
        }
        #if os(iOS)
            .task(id: thread.isAttached) { await thread.loadModelsAndUsage() }
        #endif
        .animation(.smooth(duration: 0.2), value: thread.sideQuestions)
        .animation(.smooth(duration: 0.2), value: thread.backgroundTasks)
    }

    private var box: some View {
        MessageBox(
            placeholder: placeholder, isRunning: thread.state.isRunning, canSend: thread.canSend,
            stopLabel: String(localized: "Stop \(agentName)"),
            attaching: AttachmentSending(
                attachments: $attachments, canSend: thread.canSendAttachments, isUploading: thread.isUploading,
                send: thread.send(_:attachments:)),
            replyTo: $replyTo, editing: $editing, startCall: thread.isAttached ? startCall : nil, inCall: inCall,
            commands: SlashCommands(
                list: thread.commands, load: { Task { await thread.loadCommands() } },
                prefill: Binding(get: { thread.prefill }, set: { thread.prefill = $0 })),
            chat: ChatControls(thread: thread, agentName: agentName, agentDefault: agentDefault),
            send: send, stop: thread.stop)
    }

    private func send(_ text: String) {
        guard editing else { return thread.send(text) }
        editing = false
        // A reply that started meanwhile can't be undone under it; the text goes as a new message.
        if thread.canRewind { Task { await thread.edit(text) } } else { thread.send(text) }
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
/// something runs and the box is empty. In rooms, typing `@` suggests members to mention. On
/// iPhone a chat's box opens up while you type: the text gets its own row, and below it a row of
/// buttons with the chat's context and a gauge for its model and thinking.
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
    /// Chats only: you're editing your last message; Send replaces it.
    var editing: Binding<Bool>?
    /// Chats only: starts a voice call with the agent.
    var startCall: (() -> Void)?
    /// While a call runs it has the microphone, so the box offers no mic or call.
    var inCall = false
    /// Chats only: skills and commands to offer after `/`.
    var commands: SlashCommands?
    /// Chats only: the model, thinking and context controls the iPhone shows while you type.
    var chat: ChatControls?
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
    /// iPhone: the gauge's level picker is open above the box.
    @State private var pickingLevel = false
    /// iPhone: the model sheet is open.
    @State private var choosingModel = false

    #if os(iOS)
        /// Larger than the Mac's, for thumbs: 34 pt buttons in 6 pt of padding.
        private static let buttonSize: CGFloat = 34
        private static let inset: CGFloat = 6
        private static let fontSize: CGFloat = 17
        private static let fieldPadding: CGFloat = 6
    #else
        private static let buttonSize: CGFloat = 28
        private static let inset: CGFloat = 4
        private static let fontSize: CGFloat = 15
        private static let fieldPadding: CGFloat = 4
    #endif
    /// Round ends on one line.
    private static var cornerRadius: CGFloat { buttonSize / 2 + inset }

    /// iPhone: while you type in a chat, the text gets the box's whole width and the buttons and
    /// the chat's settings move to a row below it.
    private var expanded: Bool {
        #if os(iOS)
            focused && chat != nil
        #else
            false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !menu.isEmpty {
                SuggestionMenu(
                    items: menu, highlighted: min(highlighted, menu.count - 1), highlight: { highlighted = $0 },
                    pick: pick)
            }
            #if os(iOS)
                if menu.isEmpty, pickingLevel, let chat {
                    LevelPanel(chat: chat) {
                        pickingLevel = false
                        choosingModel = true
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }
            #endif
            VStack(alignment: .leading, spacing: 4) {
                if let quote = replyTo?.wrappedValue {
                    ReplyChip(quote: quote) { replyTo?.wrappedValue = nil }
                }
                if editing?.wrappedValue == true {
                    ReplyChip(
                        text: String(localized: "Editing your last message"),
                        cancelLabel: String(localized: "Stop editing")
                    ) {
                        editing?.wrappedValue = false
                        text = ""
                    }
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
                #if os(iOS)
                    ComposerLayout(expanded: expanded) {
                        if let attaching {
                            AttachButton { attaching.attachments.append(contentsOf: $0) }
                                .layoutValue(key: ComposerLayout.RoleKey.self, value: .leading)
                        }
                        field
                        HStack(spacing: 6) {
                            if expanded, let chat {
                                ComposerControls(chat: chat, pickingLevel: $pickingLevel)
                            }
                            sendButton
                        }
                        .layoutValue(key: ComposerLayout.RoleKey.self, value: .trailing)
                    }
                #else
                    HStack(alignment: .bottom, spacing: 8) {
                        if let attaching {
                            AttachButton { attaching.attachments.append(contentsOf: $0) }
                        }
                        field
                        sendButton
                    }
                #endif
                switch dictation.state {
                case .denied(let message):
                    DictationProblem(message: message, showsSettings: true, dismiss: dictation.dismissProblem)
                case .failed(let message):
                    DictationProblem(message: message, showsSettings: false, dismiss: dictation.dismissProblem)
                default:
                    EmptyView()
                }
            }
            // On the Mac 36 pt tall on one line, like the name pill above.
            .padding(Self.inset)
            .floatingSurface(in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .environment(\.composerButtonSize, Self.buttonSize)
        .animation(.smooth(duration: 0.25), value: expanded)
        .animation(.smooth(duration: 0.2), value: pickingLevel)
        #if os(macOS)
            .onAppear { focused = true }
        #else
            // The level picker closes as you type on, put the keyboard away, or tap the chat.
            .onChange(of: text) { pickingLevel = false }
            .onChange(of: focused) { _, focused in if !focused { pickingLevel = false } }
            .sheet(isPresented: $choosingModel) {
                if let chat { ModelSheet(chat: chat) }
            }
        #endif
        .onDisappear { dictation.stop() }
        // The menu reads the gateway's list each time it opens.
        .onChange(of: slashQuery != nil) { _, open in if open { commands?.load() } }
        // Clicking or tapping the conversation closes the menus, like Escape.
        .onChange(of: conversationTaps) {
            closeMenu()
            pickingLevel = false
        }
        .onChange(of: menuText) { _, text in
            highlighted = 0
            if text != dismissedText { dismissedText = nil }
        }
        .onChange(of: commands?.prefill) { _, prefill in
            guard let prefill else { return }
            replaceText(with: prefill)
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
        guard commands != nil else { return nil }
        return Self.slashWord(in: menuText)
    }

    /// The name typed after a `/` that starts the last word: at the start of the message it's a
    /// command or skill to run; later on, one named in your text, which goes as you wrote it (as
    /// in the official app). `nil` once a space ends the word, or for paths (`/usr/bin`).
    nonisolated static func slashWord(in text: String) -> String? {
        guard let word = text.split(omittingEmptySubsequences: false, whereSeparator: \.isWhitespace).last,
            word.hasPrefix("/")
        else { return nil }
        let name = word.dropFirst()
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return String(name)
    }

    private var commandSuggestions: [SlashCommand] {
        guard let commands, let query = slashQuery else { return [] }
        let matches = commands.matching(query)
        // Typed in full: nothing left to pick.
        return matches.count == 1 && matches[0].name == "/" + query ? [] : matches
    }

    /// Puts the picked name in place of the `/word` being typed.
    private func complete(with command: SlashCommand) {
        let typed = (slashQuery?.count ?? 0) + 1
        replaceText(with: String(menuText.dropLast(typed)) + command.name + " ")
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
        .font(.system(size: Self.fontSize))
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
        .padding(.leading, expanded ? 8 : (attaching == nil ? 12 : 0))
        .padding(.vertical, Self.fieldPadding)
    }

    @ViewBuilder private var sendButton: some View {
        if attaching?.isUploading == true {
            ProgressView()
                .controlSize(.small)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .accessibilityLabel(Text("Uploading"))
        } else if isRunning, isEmpty, !hasAttachments, !dictation.isListening {
            RoundButton(systemImage: "stop.fill", label: stopLabel, action: stop)
        } else if !inCall, dictation.isListening || (isEmpty && !hasAttachments) {
            // An empty box offers the mic, as Messages and Grok Bot do; Send takes over once
            // there's something to send. In a chat, a call button sits beside it.
            HStack(spacing: 6) {
                if let startCall, !dictation.isListening, !isRunning {
                    CallStartButton(action: startCall)
                }
                MicButton(dictation: dictation) {
                    dictation.start(after: text) { text = $0 }
                    focused = true
                }
            }
        } else {
            RoundButton(systemImage: "arrow.up", label: String(localized: "Send"), action: submit)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.35)
        }
    }

    private var hasAttachments: Bool { attaching?.attachments.isEmpty == false }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// New text for the box with the cursor after it, so you type on where the pick or prefill
    /// ended (the field would otherwise keep the old cursor, mid-word).
    private func replaceText(with new: String) {
        text = new
        selection = TextSelection(insertionPoint: text.endIndex)
    }

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
        if let attaching, !attaching.attachments.isEmpty, editing?.wrappedValue != true {
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
        replaceText(with: words.joined(separator: " ") + " ")
        focused = true
    }
}

private struct RoundButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @Environment(\.composerButtonSize) private var size

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 12 / 28, weight: .bold))
                .foregroundStyle(Theme.primaryInk)
                .frame(width: size, height: size)
                .background(Theme.primary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
