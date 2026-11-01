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
    @FocusState private var fieldFocused: Bool

    /// Where a conversation stood when you sent into it: the answer shows what came after.
    struct Sent: Equatable {
        let contactID: Contact.ID
        let start: Int
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let sent, let contact = contacts.first(where: { $0.id == sent.contactID }) {
                    answerHeader(contact)
                    QuickAnswer(model: model, contact: contact, start: sent.start, agents: agentsByProfile)
                        .environment(\.chatContact, contact.kind == .agent ? contact : nil)
                    messageField(placeholder: String(localized: "Reply to \(contact.name)"))
                } else {
                    recipientRow
                    messageField(placeholder: String(localized: "Message \(recipient?.name ?? "")"))
                    WaitingOnYou(model: model, contacts: contacts, openChat: openChat)
                    keyHints
                }
            }
            .frame(width: 640)
            .floatingSurface(in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 30, y: 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A click beside the panel dismisses it, as clicking away does.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture(perform: close))
        .onAppear(perform: appeared)
        .onChange(of: shownAt) { appeared() }
        .appPreferences()
        .environment(\.botPictures, model.pictures)
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
        contacts.first { $0.id == recipientID } ?? contacts.first
    }

    private var agentsByProfile: [Contact.ID: Contact] {
        Dictionary(contacts.filter { $0.kind == .agent }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
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
            .buttonStyle(.plain)
            .opacity(canSubmit ? 1 : 0.35)
            .disabled(!canSubmit)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Theme.pane, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var keyHints: some View {
        HStack(spacing: 18) {
            KeyHint(key: "⇥", label: String(localized: "Next contact"))
            KeyHint(key: "↵", label: String(localized: "Send"))
            KeyHint(key: "⌘↵", label: String(localized: "Open chat"))
            Spacer()
            KeyHint(key: "esc", label: String(localized: "Close"))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Theme.border.frame(height: 1) }
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let about = contact.details?.description?.nonEmpty {
                    Text(about)
                        .font(.system(size: 12.5))
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
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(Capsule().strokeBorder(Theme.border))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
    }

    // MARK: - Sending

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
            let contact = sent.flatMap({ sent in contacts.first { $0.id == sent.contactID } }) ?? recipient
        else { return }
        if let room = model.room(for: contact) {
            guard room.canSend else { return }
            if sent == nil { sent = Sent(contactID: contact.id, start: room.state.items.count) }
            room.send(message)
        } else {
            let thread = model.thread(for: contact)
            model.openThread(for: contact)
            guard thread.canSend else { return }
            if sent == nil { sent = Sent(contactID: contact.id, start: thread.state.items.count) }
            thread.send(message)
        }
        recipientID = contact.id
        text = ""
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
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }

    @ViewBuilder private func chatAnswer(_ thread: ChatThread) -> some View {
        ForEach(thread.state.items.dropFirst(min(start, thread.state.items.count))) { item in
            ItemView(item: item, agentName: contact.name)
        }
        if !thread.state.draft.isEmpty {
            AgentBubble { MarkdownView(thread.state.draft) }
        } else if thread.state.isRunning, thread.approvals.isEmpty, thread.questions.isEmpty, thread.secrets.isEmpty,
            thread.vaultPrompts.isEmpty
        {
            WorkingRow(text: String(localized: "Thinking…"))
        }
        VaultCards(thread: thread, agentName: contact.name)
        ForEach(thread.approvals) { approval in
            ApprovalCard(approval: approval, agentName: contact.name) { thread.answer(approval, with: $0) }
        }
        ForEach(thread.questions) { prompt in
            QuestionCard(
                prompt: prompt, agentName: contact.name, answer: { thread.answer(prompt, with: $0) },
                skip: { thread.skip(prompt) })
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
        if names.isEmpty { return String(localized: "Agents are replying…") }
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
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.secondaryInk)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Approvals and questions across every chat and room, answered in place where they can be.
private struct WaitingOnYou: View {
    let model: AppModel
    let contacts: [Contact]
    let openChat: (Contact.ID) -> Void

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Waiting on you")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.leading, 6)
                ForEach(rows) { row in
                    WaitingRow(row: row, openChat: openChat)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .overlay(alignment: .top) { Theme.border.frame(height: 1) }
        }
    }

    private var rows: [WaitingRow.Row] {
        contacts.filter { $0.activity == .needsYou }.flatMap { contact -> [WaitingRow.Row] in
            if let room = model.room(for: contact) {
                return room.approvals.map { approval in
                    WaitingRow.Row(
                        id: approval.id, contact: contact,
                        title: String(
                            localized: "\(room.state.name(approval.memberID)) in \(contact.name) wants to run a command"
                        ),
                        command: approval.prompt.shortCommand,
                        answer: { room.answer(approval, with: $0) })
                }
            }
            let thread = model.thread(for: contact)
            let approvals = thread.approvals.map { approval in
                WaitingRow.Row(
                    id: approval.id, contact: contact,
                    title: String(localized: "\(contact.name) wants to run a command"), command: approval.shortCommand,
                    answer: { thread.answer(approval, with: $0) })
            }
            let questions = thread.questions.map { prompt in
                WaitingRow.Row(
                    id: prompt.id, contact: contact, title: String(localized: "\(contact.name) has a question"),
                    command: nil, answer: nil)
            }
            let secrets = thread.secrets.map { prompt in
                WaitingRow.Row(
                    id: prompt.id, contact: contact, title: SecretCard.title(prompt, agentName: contact.name),
                    command: nil, answer: nil)
            }
            let vault = thread.vaultPrompts.map { prompt in
                WaitingRow.Row(
                    id: prompt.id, contact: contact,
                    title: String(localized: "\(contact.name) needs you for a sign-in"),
                    command: nil, answer: nil)
            }
            return approvals + questions + secrets + vault
        }
    }
}

private struct WaitingRow: View {
    struct Row: Identifiable {
        let id: String
        let contact: Contact
        let title: String
        /// The command an approval is for; `nil` for questions and masked prompts, which open the chat.
        let command: String?
        let answer: ((ApprovalPrompt.Choice) -> Void)?
    }

    let row: Row
    let openChat: (Contact.ID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            AgentAvatar(contact: row.contact, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.ink)
                if let command = row.command {
                    Text(command)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let answer = row.answer {
                pill(String(localized: "Deny"), primary: false) { answer(.deny) }
                pill(String(localized: "Allow once"), primary: true) { answer(.once) }
            } else {
                pill(String(localized: "Open"), primary: true) { openChat(row.contact.id) }
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 16))
    }

    private func pill(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: primary ? .semibold : .regular))
                .foregroundStyle(primary ? Theme.primaryInk : Theme.ink)
                .padding(.horizontal, primary ? 14 : 12)
                .frame(height: 32)
                .background(primary ? Theme.primary : Theme.pane, in: Capsule())
                .overlay(Capsule().strokeBorder(primary ? .clear : Theme.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
        .font(.system(size: 12))
        .foregroundStyle(Theme.secondaryInk)
    }
}

private struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 5))
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
