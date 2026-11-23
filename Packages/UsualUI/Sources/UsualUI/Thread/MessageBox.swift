import HermesKit
import SwiftUI

/// The rounded message box shared by chats and rooms: a growing text field, Send, and Stop while
/// something runs and the box is empty. In rooms, typing `@` suggests members to mention. On
/// iPhone a chat's box opens up while you type: the text gets its own row, and its buttons a row
/// below it. The mic stays beside Send with text in the box, as in Grok's app; the chat's model,
/// thinking and context are in the agent's profile.
struct MessageBox: View {
    /// The chat or room this box writes to. The Mac shows the next one in the same pane, and the
    /// box goes with it.
    let conversation: Contact.ID
    /// What's typed and not sent: the conversation's draft (`Drafts`), so it's there when you
    /// come back.
    @Binding var text: String
    let placeholder: String
    let isRunning: Bool
    let canSend: Bool
    let stopLabel: String
    var mentions: [Mention] = []
    /// Chats only: files waiting to go with the message.
    var attaching: AttachmentSending?
    /// Messages you're replying to and words you added from them, quoted in front of yours.
    var quotes: Binding<[QuotedMessage]>?
    /// Chats only: you're editing your last message; Send replaces it.
    var editing: Binding<Bool>?
    /// What the box says while you edit, when it isn't your last message.
    var editingLabel: String?
    /// Chats only: starts a voice call with the agent.
    var startCall: (() -> Void)?
    /// While a call runs it has the microphone, so the box offers no mic or call.
    var inCall = false
    /// Chats: the Bot whose speech-to-text hears gateway dictation. Rooms leave it `nil`: the
    /// gateway's own profile, whatever the routing.
    var transcriptionProfile: String?
    /// Chats only: skills and commands to offer after `/`.
    var commands: SlashCommands?
    /// Chats only: on iPhone the box opens up while you type (see `expanded`).
    var opensForTyping = false
    /// Rooms: a message that didn't send, taken back into the box so its text isn't lost.
    var unsent: Binding<String?>?
    /// Chats only, while a reply runs: queues the message for when the reply ends, where Send
    /// steers it. `nil` where there's no queue.
    var queue: ((String) -> Void)?
    let send: (String) -> Void
    let stop: () -> Void

    #if os(macOS)
        @AppStorage(AppPreferences.commandReturnKey) private var commandReturn = false
        @Environment(\.messageBoxTakesTyping) private var takesTypingHere
        /// The terminal drawer's shell, when focused, takes the keys it's typed and pasted itself.
        @FocusedValue(\.shellHasFocus) private var shellHasFocus
        private var takesTyping: Bool { takesTypingHere && shellHasFocus != true }
    #endif
    /// The menu row Return picks.
    @State private var highlighted = 0
    /// When Return last picked from the menu: the field may still submit for that same press.
    @State private var pickedAt: Date?
    /// Escape closes the menu until you type again.
    @State private var dismissedText: String?
    /// Where the cursor is, to put a line break there.
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.conversationTaps) private var conversationTaps
    @State private var dictation = Dictation()
    @Environment(\.transcriber) private var transcriber
    @AppStorage(DictationSettings.engineKey) private var dictationEngine = ""
    #if os(iOS)
        @Environment(\.keyboardUp) private var keyboardUp
        /// iPhone: the box is open for typing. It opens and closes with the keyboard, in the same
        /// motion: opening on focus alone grew the box, then the keyboard pushed it up after.
        @State private var open = false
    #endif
    /// Mac: the conversation whose text has wrapped, so it gets the box's whole width until the box
    /// empties. Staying open stops the wider field from unwrapping it and the box closing again.
    @State private var wrapped: Contact.ID?
    private var hasWrapped: Bool { wrapped == conversation }

    #if os(iOS)
        /// Larger than the Mac's, for thumbs: 34 pt buttons in 6 pt of padding. They grow with the
        /// text, short of crowding the field out.
        @ScaledMetric(relativeTo: .body) private var scaledButtonSize: CGFloat = 34
        private var buttonSize: CGFloat { min(scaledButtonSize, 50) }
        private static let inset: CGFloat = 6
        private static let fontSize: CGFloat = 18
        private static let fieldPadding: CGFloat = 6
    #else
        private static let macButtonSize: CGFloat = 28
        /// Grows with the window's zoom, as the header's buttons do.
        private var buttonSize: CGFloat { Theme.zoomed(Self.macButtonSize, for: dynamicTypeSize) }
        /// On one line the box is as tall as the header's buttons (`ThreadPane.barItemHeight`).
        private static let inset: CGFloat = (ThreadPane.barItemHeight - macButtonSize) / 2
        private static let fontSize: CGFloat = 15
        private static let fieldPadding: CGFloat = 4
    #endif
    /// Round ends on one line.
    private var cornerRadius: CGFloat { buttonSize / 2 + inset }
    private var inset: CGFloat { Theme.zoomed(Self.inset, for: dynamicTypeSize) }

    /// The text gets the box's whole width and the buttons move to a row below it: on iPhone while
    /// you type in a chat, and on the Mac once your text wraps.
    private var expanded: Bool {
        #if os(iOS)
            open && opensForTyping
        #else
            hasWrapped
        #endif
    }

    var body: some View {
        // One container: the menus above the box, the box and its glass buttons are drawn together.
        GlassEffectContainer(spacing: 0) { stack }
            // ⌘. stops the reply even after Send has taken Stop's place.
            #if os(macOS)
                // From the menu bar: a default-style button in the chat's bottom bar, even a hidden
                // one, makes macOS draw a grey backing across the bar.
                .focusedSceneValue(\.stopReply, StopReplyCommand(stop: isRunning ? stop : nil))
            #else
                .background { stopShortcut }
            #endif
            .environment(\.composerButtonSize, buttonSize)
            .animation(.snappy(duration: 0.16), value: hasNothingToSay)
            #if os(macOS)
                .animation(.smooth(duration: 0.25), value: expanded)
                .onAppear { focused = true }
                .typingFocuses($focused, enabled: takesTyping)
                .pastesAttachments(enabled: attaching != nil && takesTyping, focused: focused) {
                    attaching?.attachments.append(contentsOf: $0)
                }
                .onChange(of: text) { if text.isEmpty { wrapped = nil } }
                .dictateKey(
                    enabled: takesTyping && !inCall, isListening: dictation.isListening, start: startDictation,
                    stop: { dictation.stop() })
            #else
                // Around the field, not on it: the field pastes text first and passes on what it can't.
                .modifier(
                    PastesAttachmentsOnPhone(enabled: attaching != nil) {
                        attaching?.attachments.append(contentsOf: $0)
                    }
                )
                // In the keyboard's own animation, which this change arrives in.
                .onChange(of: keyboardUp) { _, up in open = up && focused }
                .onChange(of: focused) { _, focused in
                    // Focus came to keys already up, or left with none up: no keyboard will move.
                    if focused == keyboardUp {
                        withAnimation(.smooth(duration: 0.25)) { open = focused }
                    }
                }
                // A hardware keyboard raises no keys, so the box opens a moment after focus instead.
                .task(id: focused) {
                    guard focused else { return }
                    try? await Task.sleep(for: .seconds(0.6))
                    guard !Task.isCancelled, focused, !open else { return }
                    withAnimation(.smooth(duration: 0.25)) { open = true }
                }
            #endif
            .onDisappear { dictation.leave() }
            // The next conversation gets its own text, and none of what was open over the last one.
            .onChange(of: conversation) {
                dictation.leave()
                dismissedText = nil
                selection = TextSelection(insertionPoint: text.endIndex)
            }
            // The menu reads the gateway's list each time it opens.
            .onChange(of: slashQuery != nil) { _, open in if open { commands?.load() } }
            // Clicking or tapping the conversation closes the menus, like Escape; on iPhone it puts
            // the keyboard away too, as a swipe down the conversation does.
            .onChange(of: conversationTaps) {
                closeMenu()
                #if os(iOS)
                    focused = false
                #endif
            }
            .onChange(of: menuText) { _, text in
                highlighted = 0
                if text != dismissedText { dismissedText = nil }
            }
            // Ahead of anything typed since, so neither is lost.
            .onChange(of: unsent?.wrappedValue, initial: true) { _, unsent in
                guard let unsent else { return }
                replaceText(with: isEmpty ? unsent : unsent + "\n\n" + text)
                self.unsent?.wrappedValue = nil
                focused = true
            }
            // Replying, or adding words you selected, is for typing on.
            .onChange(of: quotes?.wrappedValue.count ?? 0) { old, new in
                if new > old { focused = true }
            }
            // Initial too: the Plugins sheet fills a chat's box before the chat opens. Ahead of a
            // draft, as an unsent message is; an edit starts from the message alone.
            .onChange(of: commands?.prefill, initial: true) { _, prefill in
                guard let prefill else { return }
                replaceText(with: isEmpty || editing?.wrappedValue == true ? prefill : prefill + "\n\n" + text)
                commands?.prefill = nil
                focused = true
            }
    }

    #if os(iOS)
        /// ⌘. on a hardware keyboard.
        @ViewBuilder private var stopShortcut: some View {
            if isRunning {
                Button(stopLabel, action: stop)
                    .keyboardShortcut(".", modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    #endif

    private var stack: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !menu.isEmpty {
                SuggestionMenu(
                    items: menu, highlighted: min(highlighted, menu.count - 1), highlight: { highlighted = $0 },
                    pick: pick)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let quotes, !quotes.wrappedValue.isEmpty { QuoteChips(quotes: quotes) }
                if editing?.wrappedValue == true {
                    ReplyChip(
                        text: editingLabel ?? String(localized: "Editing your last message"),
                        cancelLabel: String(localized: "Stop editing")
                    ) {
                        // The box goes back to what you had typed before.
                        editing?.wrappedValue = false
                        selection = TextSelection(insertionPoint: text.endIndex)
                    }
                }
                if let attaching, !attaching.attachments.isEmpty {
                    AttachmentChips(attachments: attaching.$attachments)
                    if isRunning {
                        // Files can't join a running reply: they wait in the queue with the
                        // message, or, with no queue, for the reply to end.
                        Text(
                            queue != nil
                                ? "These wait in the queue with your message, and go when the reply ends."
                                : "Files go once the reply ends. Stop it to send them now."
                        )
                        .scaledFont(size: 12)
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.horizontal, 8)
                    }
                }
                // At accessibility text sizes the text always gets the whole width.
                ComposerLayout(expanded: expanded || dynamicTypeSize.isAccessibilitySize) {
                    if let attaching {
                        AttachButton { attaching.attachments.append(contentsOf: $0) }
                            .layoutValue(key: ComposerLayout.RoleKey.self, value: .leading)
                    }
                    field
                    buttons
                        .layoutValue(key: ComposerLayout.RoleKey.self, value: .trailing)
                }
                switch dictation.state {
                case .denied(let message):
                    DictationProblem(message: message, showsSettings: true, dismiss: dictation.dismissProblem)
                case .failed(let message):
                    DictationProblem(
                        message: message, showsSettings: false, useOnDevice: useOnDevice,
                        dismiss: dictation.dismissProblem)
                case .transcribing:
                    DictationTranscribing()
                default:
                    EmptyView()
                }
            }
            .padding(inset)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
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
            quotes?.wrappedValue.isEmpty == false ? String(localized: "Reply…") : placeholder, text: $text,
            selection: $selection, axis: .vertical
        )
        .textFieldStyle(.plain)
        .textInputTint()
        .scaledFont(size: Self.fontSize)
        .lineLimit(1...8)
        .focused($focused)
        // Menu completion wins over sending. A handled key can still trigger onSubmit on iOS.
        .onKeyPress(.return, phases: .down) { press in
            if !press.modifiers.contains(.shift), pickHighlighted() == .handled { return .handled }
            #if os(macOS)
                if !press.modifiers.contains(.shift),
                    !commandReturn || press.modifiers.contains(.command)
                {
                    submit(queueing: press.modifiers.contains(.option))
                } else {
                    insertLineBreak()
                }
                pickedAt = .now
                return .handled
            #else
                guard press.modifiers.contains(.shift) else { return .ignored }
                insertLineBreak()
                pickedAt = .now
                return .handled
            #endif
        }
        .onKeyPress(.downArrow) { moveHighlight(by: 1) }
        .onKeyPress(.upArrow) { moveHighlight(by: -1) }
        .onKeyPress(.tab) { pickHighlighted() }
        .onKeyPress(.escape) {
            guard !menu.isEmpty else { return .ignored }
            closeMenu()
            return .handled
        }
        .onSubmit { submit() }
        .padding(.leading, expanded ? 8 : (attaching == nil ? 12 : 0))
        #if os(macOS)
            // Clear of the scroll knob, and as far from the box's edge as the leading side.
            .padding(.trailing, expanded ? 8 : 0)
        #endif
        .padding(.vertical, Self.fieldPadding)
        #if os(macOS)
            // One line of text is 26 pt tall here at actual size. Before layout settles the
            // placeholder can measure taller, so an empty box doesn't count. Measured afresh for
            // each conversation: going from one wrapped draft to another changes nothing here.
            .background {
                let oneLine = Theme.zoomed(32, for: dynamicTypeSize)
                Color.clear
                .onGeometryChange(for: Bool.self) {
                    $0.size.height > oneLine
                } action: { isTall in
                    if isTall, !text.isEmpty { wrapped = conversation }
                }
                .id(conversation)
            }
            .fieldScrollKnob()
            .inlinePredictions()
        #endif
    }

    /// The mic, then Stop, the call button or Send. The mic stays with text in the box, as in
    /// Grok's app: dictating adds to what's there. A call holds the microphone meanwhile.
    private var buttons: some View {
        HStack(spacing: 6) {
            if !inCall {
                MicButton(dictation: dictation, throughGateway: dictatesThroughGateway, start: startDictation)
            }
            sendButton
        }
    }

    @ViewBuilder private var sendButton: some View {
        if attaching?.isUploading == true {
            ProgressView()
                .controlSize(.small)
                .frame(width: buttonSize, height: buttonSize)
                .accessibilityLabel(Text("Uploading"))
        } else if isRunning, hasNothingToSay, !hasAttachments, !dictation.isActive {
            RoundButton(systemImage: "stop.fill", label: stopLabel, prominent: false, action: stop)
        } else if !inCall, hasNothingToSay, !hasAttachments {
            // In a chat, the call button holds the spot Send takes over once there's something to send.
            if let startCall, !dictation.isActive, !isRunning {
                CallStartButton(action: startCall)
            }
        } else {
            // With files during a reply there's no steering: Queue is the one way they go.
            let queuesOnly = queue != nil && isRunning && hasAttachments
            HStack(spacing: 6) {
                if queue != nil {
                    RoundButton(
                        systemImage: "text.line.last.and.arrowtriangle.forward",
                        label: String(localized: "Queue"), prominent: queuesOnly
                    ) { submit(queueing: true) }
                    .disabled(!canSubmit)
                    .help(Text("Send when this reply ends (⌥Return)"))
                    .accessibilityHint(Text("Sends your message when this reply ends"))
                }
                if !queuesOnly {
                    RoundButton(systemImage: "arrow.up", label: String(localized: "Send")) { submit() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private var hasAttachments: Bool { attaching?.attachments.isEmpty == false }

    private func startDictation() {
        dictation.start(
            after: text, transcriber: dictatesThroughGateway ? transcriber : nil,
            profile: transcriptionProfile, current: { text }, update: { text = $0 })
        focused = true
    }

    /// "Use On-device", for a recording the gateway couldn't transcribe.
    private var useOnDevice: (() -> Void)? {
        guard dictation.canUseOnDevice else { return nil }
        let dictation = dictation
        return { dictation.useOnDevice() }
    }

    private var dictatesThroughGateway: Bool { dictationEngine == DictationSettings.gateway && transcriber != nil }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// No words of yours, in the box or under a quote: answers to quotes send on their own.
    private var hasNothingToSay: Bool { isEmpty && quotes?.wrappedValue.hasReplies != true }

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
        let cursor = text.insertLineBreak(replacing: range)
        selection = TextSelection(insertionPoint: cursor)
    }

    private var canSubmit: Bool {
        // Gateway words are still to come; sending now would leave them for the next message.
        if dictation.holdsSending { return false }
        if let attaching, !attaching.attachments.isEmpty { return attaching.canSend }
        return canSend && !hasNothingToSay
    }

    /// `queueing`: the message waits for the running reply to end, where there's a queue.
    private func submit(queueing: Bool = false) {
        // Return with a menu open picks its row. On iPhone the field submits for the same press
        // after the key handler picked, which must not send the command you just picked.
        if let pickedAt, Date.now.timeIntervalSince(pickedAt) < 0.3 {
            self.pickedAt = nil
            return
        }
        if pickHighlighted() == .handled { return }
        // Return while the gateway listens stops the recording; the words then arrive to send.
        if dictation.holdsSending {
            if dictation.isListening { dictation.stop() }
            return
        }
        guard canSubmit else { return }
        // Sending ends dictation; words still arriving would land in the next message.
        dictation.stop()
        let quoted = quotes?.wrappedValue ?? []
        if let attaching, !attaching.attachments.isEmpty, editing?.wrappedValue != true {
            // Text and files leave together once every file is up; a failure keeps both here.
            let draft = text
            let files = attaching.attachments
            putKeyboardAway()
            Task {
                guard await attaching.send(quoted.message(draft), files) else { return }
                if text == draft { text = "" }
                // Quotes added while the files went up wait for the next message.
                quotes?.wrappedValue.removeAll(where: quoted.contains)
                attaching.attachments.removeAll { sent in files.contains { $0.id == sent.id } }
            }
            return
        }
        // Emptied before it goes: sending an edit ends it, and the box is then your draft's again.
        let message = quoted.message(text)
        text = ""
        if queueing, let queue { queue(message) } else { send(message) }
        quotes?.wrappedValue = []
        putKeyboardAway()
    }

    /// iPhone: sending puts the keyboard away, so the chat has the screen for your message and
    /// the reply. A hardware keyboard raises no keys and keeps the cursor, to type the next one.
    private func putKeyboardAway() {
        #if os(iOS)
            if keyboardUp { focused = false }
        #endif
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

/// Send, in the Bot's colour, and Stop, in plain glass.
private struct RoundButton: View {
    let systemImage: String
    let label: String
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ComposerGlyph(systemImage: systemImage, scale: 12, weight: .bold, prominent: prominent)
        }
        .composerGlass(prominent: prominent)
        .accessibilityLabel(Text(label))
    }
}
