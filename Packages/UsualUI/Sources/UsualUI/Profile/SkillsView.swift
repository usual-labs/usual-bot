import HermesKit
import SwiftUI

/// The agent's skills, most used first, each with a switch. Type `/` in the chat to use one.
struct SkillsView: View {
    let list: SkillList
    let agentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch list.phase {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 20)
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await list.refresh() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .frame(maxWidth: .infinity)
            case .ready:
                if list.skills.isEmpty {
                    Text("No skills yet.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.vertical, 8)
                }
                ForEach(list.skills) { skill in
                    SkillRow(skill: skill, list: list)
                    Divider().overlay(Theme.border)
                }
                if let problem = list.problem {
                    Text(problem)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.danger)
                        .padding(.top, 10)
                }
            }
            Text("Type / in the chat to use a skill. \(agentName) also picks them up on its own when they fit.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: list.profile) { await list.refresh() }
    }
}

private struct SkillRow: View {
    let skill: Skill
    let list: SkillList

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 14))
                    .foregroundStyle(skill.enabled ? Theme.ink : Theme.secondaryInk)
                    .lineLimit(1)
                Text(skill.description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { skill.enabled }, set: { list.setEnabled($0, for: skill) })) {
                Text(skill.name)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.ink)
        }
        .padding(.vertical, 11)
        .help(origin)
    }

    /// Where the skill came from, in words.
    private var origin: String {
        switch skill.provenance {
        case "hub": String(localized: "Installed from the skills hub")
        case "bundled": String(localized: "Comes with Hermes")
        case "external": String(localized: "From a shared skills folder")
        default: String(localized: "Written for this agent")
        }
    }
}
