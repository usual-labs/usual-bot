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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 6) {
                    RoomAvatar(members: members, size: 72)
                    Text(room.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("^[\(members.count) agent](inflect: true)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(members) { member in
                        row(member)
                        if member.id != members.last?.id { Divider().overlay(Theme.border).padding(.leading, 48) }
                    }
                }
                .padding(.horizontal, 12)
                .background(Theme.pane, in: RoundedRectangle(cornerRadius: 14))

                Text("Each agent answers here with its default model. To change one, open that agent's chat and choose Make Default in its model menu.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .background(Theme.window)
    }

    private func row(_ member: Contact) -> some View {
        HStack(spacing: 12) {
            AgentAvatar(contact: still(member), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(model(of: member))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
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
