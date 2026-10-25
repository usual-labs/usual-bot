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

    /// The message you're replying to; a reply to an agent goes to that agent only.
    @State private var replyTo: QuotedMessage?
    @State private var showsInfo = false

    var body: some View {
        content
            .environment(\.messageActions, actions)
            .chatBars {
                Button {
                    showsInfo.toggle()
                } label: {
                    NamePill(contact: contact, members: members)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows the room's members"))
                .keyboardShortcut("i", modifiers: .command)
            } bottom: {
                if room.phase == .ready {
                    MessageBox(
                        placeholder: placeholder, isRunning: !room.working.isEmpty, canSend: room.canSend,
                        stopLabel: String(localized: "Stop everyone in \(contact.name)"), mentions: mentions,
                        replyTo: $replyTo, commands: roomSkills, send: room.send, stop: room.stop
                    )
                    .frame(maxWidth: 780)
                    .padding(.horizontal, 20)
                }
            }
            .onChange(of: room.roomID) {
                replyTo = nil
                showsInfo = false
            }
            .inspector(isPresented: $showsInfo) {
                RoomPanel(room: contact, members: members).inspectorColumnWidth(min: 260, ideal: 300, max: 400)
            }
            .paneChrome()
            // Rooms push nothing: read new events while the room is on screen.
            .task(id: room.roomID) {
                while !Task.isCancelled {
                    await room.sync()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch room.phase {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).multilineTextAlignment(.center)
                Button("Try Again") { Task { await room.sync() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondaryInk)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            transcript
        }
    }

    private var transcript: some View {
        ConversationScroll {
            if !room.driverRunning {
                NoticeLine(
                    text: String(localized: "The gateway's room service isn't running, so agents won't answer."))
            }
            if room.state.items.isEmpty, room.pending.isEmpty {
                NoticeLine(text: String(localized: "Say hello to everyone, or use @ to talk to one agent."))
                    .padding(.top, 40)
            }
            ForEach(room.state.items) { item in
                ItemView(item: item, agentName: contact.name, author: author)
            }
            ForEach(room.pending) { message in
                UserBubble(text: message.text)
                    .opacity(0.6)
                    .accessibilityLabel(Text("Sending: \(message.text)"))
            }
            ForEach(room.working.sorted(), id: \.self) { memberID in
                if let author = author(memberID) {
                    replyingRow(String(localized: "\(author.name) is replying…")) {
                        AgentAvatar(contact: author.contact, size: 28)
                    }
                }
            }
            if room.isBusy, room.working.isEmpty {
                // An older gateway says only that someone is answering, not who.
                replyingRow(String(localized: "Agents are replying…")) { RoomAvatar(members: members, size: 28) }
            }
            ForEach(room.approvals) { approval in
                ApprovalCard(
                    approval: approval.prompt, agentName: author(approval.memberID)?.name ?? approval.memberID
                ) { room.answer(approval, with: $0) }
            }
        }
    }

    private func replyingRow(_ text: String, @ViewBuilder avatar: () -> some View) -> some View {
        HStack(spacing: 10) {
            avatar()
            TypingIndicator()
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
        }
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
        String(localized: "Message \(contact.name) · @ to mention an agent")
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
