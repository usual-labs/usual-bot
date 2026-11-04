import HermesKit
import SwiftUI

/// A room: you and several agents in one conversation. Messages without an @mention go to every
/// agent; with mentions, only to those named.
struct RoomPane: View {
    let contact: Contact
    /// The room's members as sidebar contacts, for the header.
    let members: [Contact]
    let room: RoomThread
    /// Every agent on the gateway by profile, to give room members their sidebar look.
    let agents: [Contact.ID: Contact]
    /// A member's skills, for the `/` menu; `nil` where there are none to show.
    var skills: (Contact) -> SkillList? = { _ in nil }
    /// A message search chose in this room, to scroll to.
    var jump: MessageJump? = nil
    var jumped: () -> Void = {}

    /// The message you're replying to; a reply to an agent goes to that agent only.
    @State private var replyTo: QuotedMessage?
    @State private var showsInfo = false

    var body: some View {
        content
            .environment(\.messageActions, actions)
            .chatBars {
                NamePill(contact: contact, members: members) { showsInfo.toggle() }
                    .accessibilityHint(Text("Shows the room's members"))
            } bottom: {
                if room.phase == .ready {
                    MessageBox(
                        placeholder: placeholder, isRunning: !room.working.isEmpty, canSend: room.canSend,
                        stopLabel: String(localized: "Stop everyone in \(contact.name)"), mentions: mentions,
                        replyTo: $replyTo, commands: roomSkills,
                        unsent: Binding(get: { room.unsent }, set: { room.unsent = $0 }), send: room.send,
                        stop: room.stop
                    )
                    .frame(maxWidth: Theme.columnWidth)
                    .padding(.horizontal, ThreadPane.composerMargin)
                }
            }
            .onChange(of: room.roomID) {
                replyTo = nil
                showsInfo = false
            }
            // Inside the inspector: outside, the name drops below the window buttons' line.
            .paneChrome()
            #if os(macOS)
                .focusedSceneValue(
                    \.chatPanel,
                    ChatPanelCommand(title: showsInfo ? "Hide Room Details" : "Show Room Details") {
                        showsInfo.toggle()
                    }
                )
                .inspector(isPresented: $showsInfo) {
                    RoomPanel(room: contact, members: members)
                    .inspectorColumnWidth(min: 260, ideal: Self.panelWidth, max: 400)
                }
                .preference(key: OpenPanelWidth.self, value: showsInfo ? Self.panelWidth : 0)
            #else
                // Pushed, as a Bot's profile is. A compact inspector drops the name from the bar.
                .navigationDestination(isPresented: $showsInfo) {
                    RoomPanel(room: contact, members: members)
                }
            #endif
            // Rooms push nothing: read new events while the room is on screen.
            .task(id: room.roomID) {
                while !Task.isCancelled {
                    await room.sync()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
    }

    /// The room panel's usual width, which the window's minimum width makes room for. The split
    /// view keeps an inspector near this rather than shrinking it to its minimum.
    static let panelWidth: CGFloat = 300

    @ViewBuilder private var content: some View {
        switch room.phase {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).multilineTextAlignment(.center)
                Button("Try Again") { Task { await room.sync() } }
                    .buttonStyle(.bordered)
            }
            .scaledFont(size: 13)
            .foregroundStyle(Theme.secondaryInk)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            // As in a chat: one room's messages mustn't animate into the next.
            transcript.id(contact.id)
        }
    }

    private var transcript: some View {
        ConversationScroll(
            arrival: [room.state.items.count, room.pending.count, room.working.count, room.retries.count],
            // A message stays the same count from sending to the room confirming it.
            sent: SentMessages(count: room.state.items.count(where: \.isYours) + room.pending.count),
            jump: jump, jumped: jumped
        ) {
            if !room.driverRunning {
                NoticeLine(
                    text: String(localized: "The gateway's room service isn't running, so Bots won't answer."))
            }
            if room.state.items.isEmpty, room.pending.isEmpty {
                NoticeLine(text: String(localized: "Say hello to everyone, or use @ to talk to one Bot."))
                    .padding(.top, 40)
            }
            let dates = DateLabels.labels(for: room.state.items)
            ForEach(room.state.items) { item in
                if let date = dates[item.id] { DateLabel(text: date) }
                ItemView(item: item, agentName: contact.name, author: author)
                    .transition(.settle)
                    .accessibilityElement(children: .contain)
            }
            ForEach(room.pending) { message in
                UserBubble(text: message.text)
                    .opacity(0.6)
                    .accessibilityLabel(Text("Sending: \(message.text)"))
                    .transition(.rise)
            }
            ForEach(room.working.sorted(), id: \.self) { memberID in
                if let author = author(memberID) {
                    replyingRow(String(localized: "\(author.name) is replying…")) {
                        AgentAvatar(contact: author.contact.with(activity: .working), size: 24)
                    }
                }
            }
            if room.isBusy, room.working.isEmpty {
                // An older gateway says only that someone is answering, not who.
                replyingRow(String(localized: "Bots are replying…")) { RoomAvatar(members: members, size: 24) }
            }
            ForEach(room.approvals) { approval in
                ApprovalCard(
                    approval: approval.prompt, agentName: author(approval.memberID)?.name ?? approval.memberID
                ) { room.answer(approval, with: $0) }
            }
            ForEach(room.retries, id: \.self) { taskID in
                RetryCard(
                    agentName: room.retryMember(taskID).flatMap { author($0)?.name },
                    othersBusy: room.isBusy || !room.pending.isEmpty || room.retries.count > 1,
                    retry: { room.retry(taskID) },
                    dismiss: { room.dismiss(taskID) })
            }
        }
        .onChange(of: room.approvals.count) { old, new in
            guard let asking = room.approvals.last,
                let text = TranscriptAnnouncement.appeared(
                    from: WaitingCards(approvals: old), to: WaitingCards(approvals: new),
                    agent: author(asking.memberID)?.name ?? asking.memberID)
            else { return }
            TranscriptAnnouncement.post(text)
        }
    }

    private func replyingRow(_ text: String, @ViewBuilder avatar: () -> some View) -> some View {
        HStack(spacing: 8) {
            avatar()
            ShimmerText(text: text)
        }
        .padding(.leading, 8)
    }

    /// A member's name and avatar: the agent's own from the sidebar when it's on this gateway.
    private func author(_ memberID: String) -> MemberAuthor? {
        guard let member = room.state.member(memberID) else { return nil }
        if let profile = member.profile, let agent = agents[profile] {
            var settled = agent
            settled.activity = .idle
            return MemberAuthor(name: agent.name, contact: settled)
        }
        return MemberAuthor(
            name: room.state.name(memberID), contact: Contact(id: member.profile ?? member.id, name: member.handle))
    }

    /// Reply and copy; rooms have no reactions.
    private var actions: MessageActions {
        MessageActions(reply: { item in
            switch item.content {
            case .user(let text):
                replyTo = QuotedMessage(author: String(localized: "You"), text: text)
            case .member(let id, let text):
                let handle = room.state.member(id)?.handle
                replyTo = QuotedMessage(author: author(id)?.name ?? handle ?? id, text: text, mention: handle)
            default:
                break
            }
        })
    }

    private var mentions: [Mention] {
        room.state.members.compactMap { member in
            author(member.id).map { Mention(id: member.handle, name: $0.name, contact: $0.contact) }
        }
    }

    private var placeholder: String {
        String(localized: "Ask everyone, or @ one Bot")
    }

    /// The members' skills after `/`; reloaded each time the menu opens.
    private var roomSkills: SlashCommands {
        let lists = members.compactMap { member in skills(member).map { (member: member, list: $0) } }
        return SlashCommands(
            list: RoomSkills.commands(lists),
            load: { for (_, list) in lists { Task { await list.refresh() } } },
            prefill: .constant(nil))
    }
}

#if os(macOS)
    /// The open side panel's (profile or room) usual width; 0 with none open. The window keeps room
    /// for it, or the panel pushes the sidebar and the chat out of the window.
    struct OpenPanelWidth: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
#endif
