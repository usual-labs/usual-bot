import HermesKit
import SwiftUI

/// Everything across chats and rooms that makes a sidebar dot: approvals answered in place, room
/// replies to try again, and the rest opening their chat.
struct WaitingOnYou: View {
    let model: AppModel
    let contacts: [Contact]
    let openChat: (Contact.ID) -> Void

    var body: some View {
        let rows = Self.rows(model: model, contacts: contacts)
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
            .overlay(alignment: .top) { Divider() }
        }
    }

    static func rows(model: AppModel, contacts: [Contact]) -> [WaitingRow.Row] {
        contacts.filter { $0.activity == .needsYou }.flatMap { contact -> [WaitingRow.Row] in
            if let room = model.room(for: contact) { return rows(in: room, contact: contact) }
            let thread = model.thread(for: contact)
            let approvals = thread.approvals.map { approval in
                WaitingRow.Row(
                    id: approval.id, contact: contact,
                    title: String(localized: "\(contact.name) wants to run a command"), detail: approval.shortCommand,
                    action: .approve { thread.answer(approval, with: $0) })
            }
            let questions = thread.questions.map { prompt in
                WaitingRow.Row(
                    id: prompt.id, contact: contact, title: String(localized: "\(contact.name) has a question"))
            }
            let secrets = thread.secrets.map { prompt in
                WaitingRow.Row(
                    id: prompt.id, contact: contact, title: SecretCard.title(prompt, agentName: contact.name))
            }
            let vault = thread.vaultPrompts.map { prompt in
                WaitingRow.Row(
                    id: prompt.id, contact: contact,
                    title: String(localized: "\(contact.name) needs you for a sign-in"))
            }
            // Signing in to an app takes its card's steps, so it opens the chat.
            let apps = thread.connection.map { card in
                [WaitingRow.Row(id: card.request.id, contact: contact, title: connectTitle(card.request, contact))]
            }
            return approvals + questions + secrets + vault + (apps ?? [])
        }
    }

    static func rows(in room: RoomThread, contact: Contact) -> [WaitingRow.Row] {
        let approvals = room.approvals.map { approval in
            WaitingRow.Row(
                id: approval.id, contact: contact,
                title: String(
                    localized: "\(room.state.name(approval.memberID)) in \(contact.name) wants to run a command"),
                detail: approval.prompt.shortCommand, action: .approve { room.answer(approval, with: $0) })
        }
        let retries = room.retries.map { taskID in
            WaitingRow.Row(
                id: taskID, contact: contact, title: String(localized: "A reply in \(contact.name) didn't finish"),
                detail: String(localized: "Trying again can repeat work it already did."),
                action: .retry { room.retry(taskID) })
        }
        return approvals + retries
    }

    private static func connectTitle(_ request: ConnectionRequest, _ contact: Contact) -> String {
        if request.isList { return String(localized: "\(contact.name) wants you to connect apps") }
        let names = request.targets.map(\.title).formatted(.list(type: .and))
        return String(localized: "\(contact.name) wants to connect \(names)")
    }
}

struct WaitingRow: View {
    struct Row: Identifiable {
        enum Action {
            /// An approval, answered here.
            case approve((ApprovalPrompt.Choice) -> Void)
            /// A room reply that stopped partway, started again here.
            case retry(() -> Void)
            /// Anything else, answered in its chat.
            case open
        }

        let id: String
        let contact: Contact
        let title: String
        /// The command an approval is for, or what to know before acting.
        var detail: String?
        var action = Action.open
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
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 12.5, design: isApproval ? .monospaced : .default))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Group {
                switch row.action {
                case .approve(let answer):
                    Button("Deny") { answer(.deny) }.buttonStyle(.clickable(.bordered))
                    Button("Allow once") { answer(.once) }.buttonStyle(.inkProminent)
                case .retry(let retry):
                    Button("Open") { openChat(row.contact.id) }.buttonStyle(.clickable(.bordered))
                    Button("Try Again", action: retry).buttonStyle(.inkProminent)
                case .open:
                    Button("Open") { openChat(row.contact.id) }.buttonStyle(.inkProminent)
                }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        // A row on the panel's glass.
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var isApproval: Bool {
        if case .approve = row.action { return true }
        return false
    }
}
