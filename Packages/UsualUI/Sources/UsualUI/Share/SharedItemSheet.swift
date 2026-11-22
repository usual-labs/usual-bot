import HermesKit
import SwiftUI

/// What the share extension left, once it opened the app: what you shared, and the Bots and rooms
/// it can go to, in the sidebar's order. Choosing one puts it in that chat's message box.
struct SharedItemSheet: View {
    let item: SharedItem
    let contacts: [Contact]
    /// Hidden Bots, which still show in their rooms' pictures.
    let hiddenBots: [Contact]
    /// Puts it in the chat and returns why it couldn't, if it couldn't.
    let put: (Contact) -> String?
    let discard: () -> Void
    let close: () -> Void

    @State private var problem: String?

    var body: some View {
        SheetForm(title: Text("Send to"), cancel: close) {
            Form {
                Section {
                    Label(item.title, systemImage: symbol)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(3)
                    ForEach((item.problems ?? []) + [problem].compactMap { $0 }, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.needsYouInk)
                    }
                } footer: {
                    Text("It goes in the message box, for you to add to and send.")
                }
                Section {
                    if contacts.isEmpty {
                        Text("No Bots yet. Make one, then choose it here.")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    ForEach(contacts) { contact in
                        ShareTargetRow(
                            contact: contact, members: members(of: contact), refusal: item.problem(sendingTo: contact)
                        ) { problem = put(contact) }
                    }
                }
                Section {
                    Button("Don't Send", role: .destructive, action: discard)
                }
            }
        }
        #if os(macOS)
            .zoomedFrame(width: 420, height: 520)
        #endif
    }

    private var symbol: String {
        if !item.files.isEmpty { return item.files.count > 1 ? "doc.on.doc" : "doc" }
        return item.text.contains("://") ? "link" : "text.alignleft"
    }

    private func members(of contact: Contact) -> [Contact] {
        let byID = Dictionary((contacts + hiddenBots).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ContactList.members(of: contact, in: byID)
    }
}

/// One Bot or room to send to.
private struct ShareTargetRow: View {
    let contact: Contact
    let members: [Contact]
    /// Why what's shared can't go here; the row is then disabled and says so.
    let refusal: String?
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                Group {
                    switch contact.kind {
                    case .agent: AgentAvatar(contact: contact, size: 32)
                    case .room: RoomAvatar(members: members, size: 32)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(contact.name).lineLimit(1)
                        if contact.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryInk)
                                .accessibilityLabel(Text("Pinned"))
                        }
                    }
                    if refusal != nil {
                        Text("Text and links only").font(.caption).foregroundStyle(Theme.secondaryInk)
                    } else if contact.kind != .agent {
                        Text("Room").font(.caption).foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .opacity(refusal == nil ? 1 : 0.45)
        }
        .buttonStyle(.clickable)
        .foregroundStyle(Theme.ink)
        .disabled(refusal != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(refusal ?? ""))
    }
}
