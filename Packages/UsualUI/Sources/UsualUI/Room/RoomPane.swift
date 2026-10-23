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

    var body: some View {
        content
            .chatBars {
                NamePill(contact: contact, members: members)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            } bottom: {
                if room.phase == .ready {
                    MessageBox(
                        placeholder: placeholder, isRunning: !room.working.isEmpty, canSend: room.canSend,
                        stopLabel: String(localized: "Stop everyone in \(contact.name)"), mentions: mentions,
                        send: room.send, stop: room.stop
                    )
                    .frame(maxWidth: 780)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 8)
                }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
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
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
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

    private var mentions: [Mention] {
        room.state.members.compactMap { member in
            author(member.id).map { Mention(id: member.handle, name: $0.name, contact: $0.contact) }
        }
    }

    private var placeholder: String {
        String(localized: "Message \(contact.name) · @ to mention an agent")
    }
}
