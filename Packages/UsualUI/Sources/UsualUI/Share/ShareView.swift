import HermesKit
import SwiftUI

/// The share extension's whole screen: what you're sharing, a note, and the Bots and rooms it can
/// go to, in the sidebar's order. Sending leaves the item in the folder the app shares
/// (`ShareContainer`). On iPhone `ShareSender` then sends it from here when it can, and closes;
/// otherwise the app sends it the next time it's open (`docs/agents/decisions.md`).
public struct ShareView: View {
    let providers: [NSItemProvider]
    let container: ShareContainer?
    let sender: ShareSender?
    /// Closes the extension: the item is saved, or there was nothing to do.
    let done: () -> Void
    let cancel: () -> Void

    public init(
        providers: [NSItemProvider], container: ShareContainer?, sender: ShareSender? = nil,
        done: @escaping () -> Void, cancel: @escaping () -> Void
    ) {
        self.providers = providers
        self.container = container
        self.sender = sender
        self.done = done
        self.cancel = cancel
    }

    /// What happened to the item once you tapped Send.
    private enum Phase: Equatable {
        case sending(Contact)
        case sent(Contact)
        /// Left for the app, with why when there's more to say.
        case waiting(Contact, String?)
        case unconfirmed(Contact)
    }

    @State private var roster: ShareRoster?
    @State private var pictures: BotPictures?
    @State private var content: SharedContent?
    @State private var note = ""
    @State private var selection: Contact.ID?
    @State private var phase: Phase?
    @State private var isClosing = false
    @State private var problem: String?
    /// Items from earlier that the app hasn't sent yet.
    @State private var waiting = 0
    @State private var incoming = FileManager.default.temporaryDirectory.appending(
        path: "Shared-\(UUID().uuidString)", directoryHint: .isDirectory)

    public var body: some View {
        VStack(spacing: 0) {
            bar
            Divider().overlay(Theme.border)
            Group {
                if let phase {
                    outcome(phase)
                } else if container == nil {
                    notice(
                        "square.and.arrow.up.trianglebadge.exclamationmark",
                        String(localized: "This build of Usual Bot can't take shared items"),
                        String(localized: "It was built without the App Group that sharing needs."))
                } else if let roster, let content {
                    if roster.contacts.isEmpty {
                        notice(
                            "person.crop.circle.badge.plus", String(localized: "No Bots yet"),
                            String(localized: "Make a Bot in Usual Bot, then share again."))
                    } else {
                        picker(roster, content)
                    }
                } else if content != nil {
                    notice(
                        "person.crop.circle.badge.questionmark", String(localized: "Sign in to Usual Bot first"),
                        String(localized: "Open Usual Bot and sign in to your Hermes gateway, then share again."))
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Theme.window)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .environment(\.botPictures, pictures)
        .task { await load() }
        .onDisappear { try? FileManager.default.removeItem(at: incoming) }
    }

    // MARK: - Parts

    private var bar: some View {
        HStack {
            if phase == nil {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if case .sending = phase {
                // Nothing to press until it's gone or left for the app.
            } else if phase != nil {
                Button("Done", action: close)
                    .fontWeight(.semibold)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Send", action: save)
                    .fontWeight(.semibold)
                    .keyboardShortcut(.defaultAction)
                    .disabled(recipient == nil)
            }
        }
        .buttonStyle(.clickable)
        .overlay {
            Text("Usual Bot").font(.headline).accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func picker(_ roster: ShareRoster, _ content: SharedContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    if !content.isEmpty {
                        Label(content.summary, systemImage: symbol(for: content))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(3)
                    }
                    ForEach(content.problems + [problem].compactMap { $0 }, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.needsYouInk)
                    }
                    if !content.isEmpty {
                        TextField("Add a note", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Theme.pane, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                    }
                }
                if !content.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send to")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(roster.contacts) { contact in
                            ShareTargetRow(
                                contact: contact, members: roster.members(of: contact),
                                isSelected: contact.id == selection, refusal: content.problem(sendingTo: contact)
                            ) { selection = contact.id }
                        }
                    }
                }
                if waiting > 0 {
                    Text(
                        waiting == 1
                            ? String(localized: "1 earlier item hasn't been sent yet. Open Usual Bot to send it.")
                            : String(
                                localized:
                                    "\(waiting) earlier items haven't been sent yet. Open Usual Bot to send them."
                            )
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func outcome(_ phase: Phase) -> some View {
        switch phase {
        case .sending(let contact):
            VStack(spacing: 14) {
                ProgressView()
                Text("Sending to \(contact.name)…").font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .sent(let contact):
            notice(
                "checkmark.circle", String(localized: "Sent to \(contact.name)"),
                String(localized: "The reply shows in Usual Bot."))
        case .waiting(let contact, let reason):
            notice(
                "tray.and.arrow.up", String(localized: "Waiting to send to \(contact.name)"),
                reason
                    ?? String(
                        localized:
                            "Usual Bot sends it the next time it's open, and it shows in the chat. Until then it waits on this device."
                    ))
        case .unconfirmed(let contact):
            notice(
                "questionmark.circle", String(localized: "Couldn't tell if it reached \(contact.name)"),
                String(
                    localized:
                        "Open Usual Bot and check the chat. If it isn't there, send it again from the list of shared items."
                ))
        }
    }

    private func notice(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityHidden(true)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func symbol(for content: SharedContent) -> String {
        if !content.files.isEmpty { return content.files.count > 1 ? "doc.on.doc" : "doc" }
        return content.links.isEmpty ? "text.alignleft" : "link"
    }

    // MARK: - Doing

    /// The chosen contact, when what's shared can go to it.
    private var recipient: Contact? {
        guard let content, !content.isEmpty,
            let contact = roster?.contacts.first(where: { $0.id == selection }),
            content.problem(sendingTo: contact) == nil
        else { return nil }
        return contact
    }

    private func load() async {
        guard content == nil else { return }
        let roster = container?.roster()
        self.roster = roster
        if let roster {
            pictures = BotPictures(pictures: roster.pictures)
            waiting = container?.items().count { $0.gateway == roster.gateway } ?? 0
        }
        let content = await ShareLoader.load(providers, into: incoming)
        self.content = content
        // Start where you last shared to, when this can go there.
        if let last = container?.lastContactID, let contact = roster?.contacts.first(where: { $0.id == last }),
            content.problem(sendingTo: contact) == nil
        {
            selection = last
        }
    }

    private func save() {
        guard let container, let roster, let content, let recipient else { return }
        let item: SharedItem
        do {
            item = try container.add(content, note: note, to: recipient, gateway: roster.gateway)
        } catch {
            problem = String(localized: "Couldn't save it to send: \(error.localizedDescription)")
            return
        }
        guard let sender else { return show(.waiting(recipient, nil)) }
        show(.sending(recipient))
        Task {
            switch await sender.send(item, to: recipient, roster: roster) {
            case .sent:
                show(.sent(recipient))
                // Long enough to read; nothing's left to do here.
                try? await Task.sleep(for: .seconds(1.2))
                close()
            case .waiting(let reason): show(.waiting(recipient, reason))
            case .unconfirmed: show(.unconfirmed(recipient))
            }
        }
    }

    /// Done, by hand or after Sent, closes once.
    private func close() {
        guard !isClosing else { return }
        isClosing = true
        done()
    }

    private func show(_ phase: Phase) {
        self.phase = phase
        // VoiceOver hears what happened without finding it on the screen.
        let words: String? =
            switch phase {
            case .sending: nil
            case .sent(let contact): String(localized: "Sent to \(contact.name)")
            case .waiting(let contact, _): String(localized: "Waiting to send to \(contact.name)")
            case .unconfirmed(let contact): String(localized: "Couldn't tell if it reached \(contact.name)")
            }
        if let words { AccessibilityNotification.Announcement(words).post() }
    }
}

/// One Bot or room in the picker.
private struct ShareTargetRow: View {
    let contact: Contact
    let members: [Contact]
    let isSelected: Bool
    /// Why what's shared can't go here; the row is then disabled and says so.
    let refusal: String?
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                Group {
                    switch contact.kind {
                    case .agent: AgentAvatar(contact: contact, size: 36)
                    case .room: RoomAvatar(members: members, size: 36)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(contact.name).font(.body).lineLimit(1)
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
                if isSelected {
                    Image(systemName: "checkmark").fontWeight(.semibold).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .zoomedFrame(minHeight: 44)
            .background(isSelected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .opacity(refusal == nil ? 1 : 0.45)
        }
        .buttonStyle(.clickable)
        .disabled(refusal != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text(refusal ?? ""))
    }
}
