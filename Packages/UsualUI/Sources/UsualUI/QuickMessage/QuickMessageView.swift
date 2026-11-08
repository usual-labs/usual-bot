import HermesKit
import SwiftUI

/// The quick message panel: pick an agent or room, send, and read the answer without leaving what
/// you're doing. Below the message box, anything waiting on your decision.
public struct QuickMessageView: View {
    let model: AppModel
    /// Changes each time the panel is shown: it starts a new message unless an answer is coming.
    let shownAt: Date
    let openChat: (Contact.ID) -> Void
    let close: () -> Void

    public init(model: AppModel, shownAt: Date, openChat: @escaping (Contact.ID) -> Void, close: @escaping () -> Void) {
        self.model = model
        self.shownAt = shownAt
        self.openChat = openChat
        self.close = close
    }

    /// Who the last quick message went to; the panel starts there.
    @AppStorage("quickRecipient") private var recipientID: Contact.ID?
    /// The conversation you started from the panel; `nil` while writing a new message.
    @State private var sent: Sent?
    @State private var text = ""
    /// A message held until its chat opens.
    @State private var queued: Queued?
    /// Why the last message didn't send; it's still in the box.
    @State private var problem: String?
    @FocusState private var fieldFocused: Bool

    /// Where a conversation stood when you sent into it: the answer shows what came after.
    struct Sent: Equatable {
        let contactID: Contact.ID
        let start: Int
    }

    struct Queued: Equatable {
        let contactID: Contact.ID
        let text: String
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let sent, let contact = contacts.first(where: { $0.id == sent.contactID }) {
                    answerHeader(contact)
                    QuickAnswer(model: model, contact: contact, start: sent.start, agents: agentsByProfile)
                        .environment(\.chatContact, contact.kind == .agent ? contact : nil)
                        .environment(\.mediaProfile, contact.details?.profile ?? contact.id)
                    messageField(placeholder: String(localized: "Reply to \(contact.name)"))
                } else {
                    recipientRow
                    messageField(placeholder: String(localized: "Message \(recipient?.name ?? "")"))
                    WaitingOnYou(model: model, contacts: contacts, openChat: openChat)
                    keyHints
                }
            }
            .frame(width: 640)
            // Liquid Glass over whatever's behind the panel, as Spotlight floats.
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            Spacer(minLength: 0)
        }
        .tint(Theme.ink)
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A click beside the panel dismisses it, as clicking away does.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture(perform: close))
        .onAppear(perform: appeared)
        .onChange(of: shownAt) { appeared() }
        .onChange(of: queuedReadiness) { _, readiness in sendQueued(readiness) }
        .onChange(of: model.link) { _, link in
            guard case .online = link else { return }
            problem = nil
            // Chats open only while online, so one asked for while connecting opens now.
            if let contact = queuedContact, model.room(for: contact) == nil { model.openThread(for: contact) }
        }
        .onChange(of: recipientID) { problem = nil }
        .appPreferences()
        .environment(\.botPictures, model.pictures)
        .environment(\.media, model.media)
        .environment(\.playbackScope, "panel")
        #if os(macOS)
            .onExitCommand(perform: close)
        #endif
    }

    // MARK: - Composing

    /// Agents and rooms, in sidebar order.
    private var contacts: [Contact] {
        model.sidebarContacts.sorted(by: Contact.rosterOrder)
    }

    private var recipient: Contact? {
        // A Bot renamed on the gateway stays the one you last wrote to.
        let id = recipientID.map(model.currentID(for:))
        return contacts.first { $0.id == id } ?? contacts.first
    }

    /// With hidden Bots, which still speak in rooms.
    private var agentsByProfile: [Contact.ID: Contact] {
        Dictionary(
            (contacts + model.hiddenBots).filter { $0.kind == .agent }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
    }

    private var recipientRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(contacts) { contact in
                    RecipientButton(
                        contact: contact, members: members(of: contact), isSelected: contact.id == recipient?.id
                    ) { recipientID = contact.id }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Send to"))
    }

    private func members(of contact: Contact) -> [Contact] {
        guard case .room(let ids) = contact.kind else { return [] }
        return ids.compactMap { agentsByProfile[$0] }
    }

    private func messageField(placeholder: String) -> some View {
        VStack(spacing: 0) {
            messageBox(placeholder: placeholder)
            QuickSendStatus(waitingFor: queuedContact?.name, problem: problem) {
                if text.isEmpty, let queued { text = queued.text }
                queued = nil
            }
        }
    }

    private func messageBox(placeholder: String) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .scaledFont(size: 17)
                .focused($fieldFocused)
                .onSubmit(submit)
                #if os(macOS)
                    .onKeyPress(.tab, phases: .down) { press in
                        guard sent == nil else { return .ignored }
                        recipientID = Self.cycle(
                            contacts.map(\.id), from: recipient?.id, by: press.modifiers.contains(.shift) ? -1 : 1)
                        return .handled
                    }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command), let id = sent?.contactID ?? recipient?.id else {
                            return .ignored
                        }
                        openChat(id)
                        return .handled
                    }
                #endif
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.primaryInk)
                    .frame(width: 36, height: 36)
                    .background(Theme.primary, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.clickable)
            .opacity(canSubmit ? 1 : 0.35)
            .disabled(!canSubmit)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        // A field on the glass, not glass on glass.
        .background(.fill.tertiary, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var keyHints: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 18) {
                KeyHint(key: "⇥", label: String(localized: "Next contact"))
                KeyHint(key: "↵", label: String(localized: "Send"))
                KeyHint(key: "⌘↵", label: String(localized: "Open chat"))
                Spacer()
                KeyHint(key: "esc", label: String(localized: "Close"))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Answering

    private func answerHeader(_ contact: Contact) -> some View {
        HStack(spacing: 12) {
            switch contact.kind {
            case .agent: AgentAvatar(contact: contact, size: 32)
            case .room: RoomAvatar(members: members(of: contact), size: 32)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(contact.name)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                if let about = contact.details?.description?.nonEmpty {
                    Text(about)
                        .scaledFont(size: 12.5)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                openChat(contact.id)
            } label: {
                HStack(spacing: 8) {
                    Text("Open chat")
                    KeyCap(key: "⌘↵")
                }
            }
            .buttonStyle(.clickable(.bordered))
            .buttonBorderShape(.capsule)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Sending

    /// One message waits for its chat at a time.
    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && queued == nil
    }

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit,
            let contact = sent.flatMap({ sent in contacts.first { $0.id == sent.contactID } }) ?? recipient
        else { return }
        problem = nil
        if model.room(for: contact) == nil { model.openThread(for: contact) }
        switch readiness(of: contact) {
        case .ready: send(message, to: contact)
        case .opening: queued = Queued(contactID: contact.id, text: message)
        case .blocked(let reason):
            problem = reason
            AccessibilityNotification.Announcement(reason).post()
            return
        }
        recipientID = contact.id
        text = ""
    }

    private func send(_ message: String, to contact: Contact) {
        if let room = model.room(for: contact) {
            if sent == nil { sent = Sent(contactID: contact.id, start: room.state.items.count) }
            room.send(message)
        } else {
            let thread = model.thread(for: contact)
            if sent == nil { sent = Sent(contactID: contact.id, start: thread.state.items.count) }
            thread.send(message)
        }
    }

    private func readiness(of contact: Contact) -> QuickSend {
        if let room = model.room(for: contact) {
            return QuickSend.readiness(
                canSend: room.canSend, link: model.link, failure: room.phase.failure,
                roomServiceStopped: !room.driverRunning)
        }
        let thread = model.thread(for: contact)
        return QuickSend.readiness(canSend: thread.canSend, link: model.link, failure: thread.phase.failure)
    }

    private var queuedContact: Contact? {
        queued.flatMap { queued in contacts.first { $0.id == queued.contactID } }
    }

    /// Watched while a message waits, so it goes as soon as its chat opens.
    private var queuedReadiness: QuickSend? {
        queuedContact.map(readiness(of:))
    }

    private func sendQueued(_ readiness: QuickSend?) {
        guard let queued, let contact = queuedContact, let readiness else { return }
        switch readiness {
        case .opening: return
        case .ready: send(queued.text, to: contact)
        case .blocked(let reason):
            // Back in the box, with why.
            if text.isEmpty { text = queued.text }
            problem = reason
            AccessibilityNotification.Announcement(reason).post()
        }
        self.queued = nil
    }

    /// The panel closed: what played in it stops. (It's hidden, not removed, so its views don't
    /// disappear.)
    public static func panelClosed() {
        MediaPlayback.shared.stop(in: "panel")
    }

    /// Each time the panel opens: a new message, unless the last answer is still coming.
    private func appeared() {
        if let sent, !isAnswering(sent) { self.sent = nil }
        fieldFocused = true
    }

    private func isAnswering(_ sent: Sent) -> Bool {
        guard let contact = contacts.first(where: { $0.id == sent.contactID }) else { return false }
        if let room = model.room(for: contact) { return room.activity != .idle }
        return model.thread(for: contact).activity != .idle
    }

    /// The next recipient for ⇥ (or the previous for ⇧⇥), wrapping around.
    nonisolated static func cycle(_ ids: [Contact.ID], from current: Contact.ID?, by step: Int) -> Contact.ID? {
        guard !ids.isEmpty else { return nil }
        let index = current.flatMap { ids.firstIndex(of: $0) } ?? 0
        return ids[(index + step + ids.count) % ids.count]
    }
}

/// What came back since you sent from the panel: replies, the agent at work, and approvals.
private struct QuickAnswer: View {
    let model: AppModel
    let contact: Contact
    let start: Int
    let agents: [Contact.ID: Contact]
    @AppStorage(AppPreferences.streamRepliesKey) private var streamsReplies = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let room = model.room(for: contact) {
                    roomAnswer(room)
                } else {
                    chatAnswer(model.thread(for: contact))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .thinScroller()
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }

    @ViewBuilder private func chatAnswer(_ thread: ChatThread) -> some View {
        let items = thread.state.items
        ForEach(Array(zip(items.indices, items).dropFirst(min(start, items.count))), id: \.1.id) { index, _ in
            ItemView(
                item: TranscriptView.shown(items, at: index), agentName: contact.name,
                spokenTexts: TranscriptView.spokenTexts(in: items, at: index))
        }
        if streamsReplies, !thread.state.draft.isEmpty {
            AgentBubble { MarkdownView(thread.state.draft, isBeingWritten: true) }
        } else if thread.state.isRunning, thread.approvals.isEmpty, thread.questions.isEmpty, thread.secrets.isEmpty,
            thread.vaultPrompts.isEmpty, thread.connection == nil
        {
            WorkingRow(text: thread.state.draft.isEmpty ? String(localized: "Thinking…") : WorkingRow.writing)
        }
        VaultCards(thread: thread, agentName: contact.name)
        if let card = thread.connection { ConnectCard(thread: thread, card: card, agentName: contact.name) }
        ForEach(thread.approvals) { approval in
            ApprovalCard(approval: approval, agentName: contact.name) { thread.answer(approval, with: $0) }
        }
        ForEach(thread.questions) { prompt in
            QuestionCard(
                prompt: prompt, agentName: contact.name, answer: { thread.answer(prompt, with: $0) },
                skip: { thread.skip(prompt) },
                answersFromBox: thread.questionTheBoxAnswers?.id == prompt.id)
        }
        ForEach(thread.secrets) { prompt in
            SecretCard(
                prompt: prompt, agentName: contact.name, isUnencrypted: thread.isLinkUnencrypted,
                answer: { thread.answer(prompt, with: $0) }, skip: { thread.skip(prompt) })
        }
    }

    @ViewBuilder private func roomAnswer(_ room: RoomThread) -> some View {
        ForEach(room.state.items.dropFirst(min(start, room.state.items.count))) { item in
            ItemView(item: item, agentName: contact.name) { author(in: room, $0) }
        }
        ForEach(room.pending) { message in
            UserBubble(text: message.text).opacity(0.6)
        }
        if room.isBusy {
            ShimmerText(text: replyingLine(room))
        }
        ForEach(room.approvals) { approval in
            ApprovalCard(approval: approval.prompt, agentName: room.state.name(approval.memberID)) {
                room.answer(approval, with: $0)
            }
        }
    }

    private func replyingLine(_ room: RoomThread) -> String {
        let names = room.working.sorted().map { author(in: room, $0)?.name ?? room.state.name($0) }
        if names.isEmpty { return String(localized: "Bots are replying…") }
        return String(localized: "\(ListFormatter.localizedString(byJoining: names)) replying…")
    }

    private func author(in room: RoomThread, _ memberID: String) -> MemberAuthor? {
        guard let member = room.state.member(memberID) else { return nil }
        if let profile = member.profile, var agent = agents[profile] {
            agent.activity = .idle
            return MemberAuthor(name: agent.name, contact: agent)
        }
        return MemberAuthor(
            name: room.state.name(memberID), contact: Contact(id: member.profile ?? member.id, name: member.handle))
    }
}

/// An agent or room to send to: its avatar and name, ringed when picked.
private struct RecipientButton: View {
    let contact: Contact
    let members: [Contact]
    let isSelected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                Group {
                    switch contact.kind {
                    case .agent: AgentAvatar(contact: contact, size: 40)
                    case .room: RoomAvatar(members: members, size: 40)
                    }
                }
                .padding(2)
                .overlay(Circle().strokeBorder(isSelected ? Theme.ink : .clear, lineWidth: 2))
                Text(contact.name)
                    .scaledFont(size: 12)
                    .foregroundStyle(isSelected ? Theme.ink : Theme.secondaryInk)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clickable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            KeyCap(key: key)
            Text(label)
        }
        .scaledFont(size: 12)
        .foregroundStyle(Theme.secondaryInk)
    }
}

private struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .scaledFont(size: 12)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5))
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
