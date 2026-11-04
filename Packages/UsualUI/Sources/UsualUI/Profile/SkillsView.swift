import HermesKit
import SwiftUI

/// The agent's skills, most used first, each with a switch. Type `/` in the chat to use one.
struct SkillsView: View {
    let list: SkillList
    let agentName: String
    /// The Mac panel's Bot and tabs, above the page.
    var top: AnyView? = nil

    var body: some View {
        ProfileForm(top: top) {
            Section {
                switch list.phase {
                case .loading:
                    ProfileLoading()
                case .failed(let message):
                    ProfileFailure(message: message) { await list.refresh() }
                case .ready:
                    if list.skills.isEmpty {
                        Text("No skills yet.").foregroundStyle(.secondary)
                    }
                    #if os(macOS)
                        // The Mac's grouped form builds every row as the tab opens, which held a
                        // Bot with a hundred skills up for half a second; this builds the rows in
                        // sight. iPhone's form is already lazy.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(list.skills) { skill in
                                SkillRow(skill: skill, list: list).padding(.vertical, 6)
                                if skill.id != list.skills.last?.id { Divider() }
                            }
                        }
                    #else
                        ForEach(list.skills) { skill in
                            SkillRow(skill: skill, list: list)
                        }
                    #endif
                    if let problem = list.problem {
                        Text(problem).foregroundStyle(Theme.danger)
                    }
                }
            } footer: {
                Text("Type / in the chat to use a skill. \(agentName) also picks them up on its own when they fit.")
            }
        }
        .task(id: list.profile) { await list.refresh() }
    }
}

private struct SkillRow: View {
    let skill: Skill
    let list: SkillList

    var body: some View {
        #if os(macOS)
            // In the lazy stack, outside the form's rows: laid out as one.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                    Text(skill.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Toggle(isOn: isOn) { Text(skill.name) }.labelsHidden()
            }
            .help(origin)
        #else
            // The form styles the second line as the row's subtitle.
            Toggle(isOn: isOn) {
                Text(skill.name)
                Text(skill.description).lineLimit(2)
            }
        #endif
    }

    private var isOn: Binding<Bool> {
        Binding(get: { skill.enabled }, set: { list.setEnabled($0, for: skill) })
    }

    /// Where the skill came from, in words.
    private var origin: String {
        switch skill.provenance {
        case "hub": String(localized: "Installed from the skills hub")
        case "bundled": String(localized: "Comes with Hermes")
        case "external": String(localized: "From a shared skills folder")
        default: String(localized: "Written for this Bot")
        }
    }
}
