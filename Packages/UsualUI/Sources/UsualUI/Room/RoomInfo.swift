import HermesKit
import SwiftUI

/// The room's `/` menu: every member's switched-on skills, named with the members that have them.
/// A room message is text to its members, so a picked skill goes into your words as `/name` for
/// them to use; commands, which run on one agent's own chat, aren't offered here.
@MainActor
enum RoomSkills {
    static func commands(_ lists: [(member: Contact, list: SkillList)]) -> [SlashCommand] {
        var owners: [String: [String]] = [:]
        var descriptions: [String: String] = [:]
        var order: [String] = []
        for (member, list) in lists {
            for skill in list.skills where skill.enabled {
                if owners[skill.name] == nil { order.append(skill.name) }
                owners[skill.name, default: []].append(member.name)
                descriptions[skill.name] = descriptions[skill.name] ?? skill.description
            }
        }
        return order.map { name in
            let who = owners[name, default: []].joined(separator: ", ")
            let description = descriptions[name].map { $0.isEmpty ? who : "\(who) · \($0)" } ?? who
            return SlashCommand(name: "/" + name, description: description, kind: .skill)
        }
    }
}

/// Who's in the room and which model each answers with, beside the conversation. Members answer
/// with their agent's default model; it changes from the agent's own chat (Make Default).
struct RoomPanel: View {
    let room: Contact
    let members: [Contact]
    /// The room itself, for who leads it and who answers.
    let thread: RoomThread

    @Environment(\.roomEditing) private var editing
    @State private var edit: RoomEdit?
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 6) {
                    RoomAvatar(members: members, size: 72)
                    Text(room.name)
                        .scaledFont(size: 20, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                    Text("^[\(members.count) Bot](inflect: true)")
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.secondaryInk)
                    if let purpose = thread.settings?.purpose, !purpose.isEmpty {
                        Text(purpose)
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .accessibilityLabel(Text("Purpose: \(purpose)"))
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(members) { member in
                        row(member)
                        if member.id != members.last?.id { Divider().overlay(Self.line).padding(.leading, 48) }
                    }
                }
                .padding(.horizontal, 12)
                .background(Self.card, in: RoundedRectangle(cornerRadius: 14))

                Text(
                    "Each Bot answers here with its default model. To change one, open that Bot's chat and choose Make Default in its model menu."
                )
                .scaledFont(size: 12)
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

                whoAnswers

                if let editing {
                    VStack(spacing: 0) {
                        if thread.settings != nil {
                            action("Room Settings…") { showsSettings = true }
                            Divider().overlay(Self.line)
                        }
                        action("Rename Room…") { edit = .rename(room) }
                        Divider().overlay(Self.line)
                        action("Delete Room…", role: .destructive) { edit = .delete(room) }
                    }
                    .padding(.horizontal, 12)
                    .background(Self.card, in: RoundedRectangle(cornerRadius: 14))
                    .disabled(editing.unavailable != nil)

                    if let reason = editing.unavailable { footnote(reason) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .thinScroller()
        #if os(macOS)
            .background(Theme.window)
        #else
            // A page pushed from the room, like a Bot's profile.
            .background(Theme.groupedPage)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .roomEditor($edit)
        .sheet(isPresented: $showsSettings) {
            if let settings = thread.settings, let editing {
                RoomSettingsSheet(
                    current: settings, modes: thread.routingModes, members: leadChoices,
                    unavailable: editing.unavailable
                ) { try await editing.saveSettings(room, $0) }
            }
        }
    }

    /// Who answers a message that names nobody, and what the room keeps in mind.
    @ViewBuilder private var whoAnswers: some View {
        if let settings = thread.settings, !thread.routingModes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Who answers")
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Theme.secondaryInk)
                Text(settings.whoAnswers(lead: thread.leadID.map(name)))
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(Theme.ink)
                Text(settings.routing.explanation)
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if !settings.notes.isEmpty {
                    Divider().overlay(Self.line).padding(.vertical, 6)
                    Text("Notes")
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(Theme.secondaryInk)
                    Text(settings.notes)
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Self.card, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
        } else if thread.phase == .ready {
            footnote(
                String(
                    localized:
                        "Every Bot answers a message without an @mention. Choosing a lead, or letting the room pick, needs Hermes 0.23 or later on the gateway."
                ))
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 12)
            .foregroundStyle(Theme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A member's name: its Bot's sidebar name where it's on this gateway.
    private func name(_ memberID: String) -> String {
        contact(of: memberID)?.name ?? thread.state.name(memberID)
    }

    private func contact(of memberID: String) -> Contact? {
        guard let profile = thread.state.member(memberID)?.profile else { return nil }
        return members.first { ($0.details?.profile ?? $0.id) == profile }
    }

    private var leadChoices: [LeadChoice] {
        thread.state.members.map { LeadChoice(id: $0.id, name: name($0.id)) }
    }

    #if os(macOS)
        private static let card = Theme.pane
        private static let line = Theme.border
    #else
        private static let card = Theme.groupedCard
        private static let line = Theme.groupedBorder
    #endif

    /// A list row's button: borderless, so its role colours Delete.
    private func action(_ title: LocalizedStringKey, role: ButtonRole? = nil, perform: @escaping () -> Void)
        -> some View
    {
        Button(role: role, action: perform) {
            Text(title)
                .scaledFont(size: 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.clickable(.borderless))
    }

    private func row(_ member: Contact) -> some View {
        HStack(spacing: 12) {
            AgentAvatar(contact: still(member), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Theme.ink)
                    if isLead(member) {
                        Text("Lead")
                            .scaledFont(size: 11, weight: .medium)
                            .foregroundStyle(Theme.secondaryInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
                Text(model(of: member))
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1, accessibility: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func isLead(_ member: Contact) -> Bool {
        guard let lead = thread.leadID else { return false }
        return contact(of: lead)?.id == member.id
    }

    private func model(of member: Contact) -> String {
        guard let model = member.details?.model else { return String(localized: "Model not reported") }
        return [ModelControls.short(model), member.details?.provider].compactMap(\.self).joined(separator: " · ")
    }

    private func still(_ contact: Contact) -> Contact {
        var copy = contact
        copy.activity = .idle
        return copy
    }
}
