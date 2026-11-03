import HermesKit
import SwiftUI

/// Starts a room: the agents in it and a name, which defaults to theirs. The gateway seats two to
/// six agents.
struct NewRoomSheet: View {
    /// The agents on this gateway, in sidebar order.
    let agents: [Contact]
    /// Creates the room and returns its contact ID.
    let create: (String, [Contact]) async throws -> Contact.ID
    /// Told the new room's contact ID, to open it.
    let created: (Contact.ID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// Picked agents, in the order you picked them; the room lists them that way.
    @State private var picked: [Contact.ID] = []
    @State private var isCreating = false
    @State private var problem: String?

    static let seats = 2...6

    var body: some View {
        SheetForm(
            title: Text("New Room"), cancel: { dismiss() },
            action: SheetAction(title: "Create", isEnabled: canCreate, perform: submit),
            busy: isCreating ? "Creating…" : nil
        ) {
            form
                #if os(macOS)
                    .scrollContentBackground(.hidden)
                #endif
        }
        #if os(macOS)
            .frame(width: 420, height: 560)
            .presentationBackground(Theme.pane)
        #endif
    }

    private var form: some View {
        Form {
            Section {
                // Left blank, the room takes its agents' names.
                TextField("Name", text: $name, prompt: Text(suggestion.isEmpty ? "Room name" : suggestion))
                    .onSubmit(submit)
            }
            Section {
                ForEach(agents) { row($0) }
            } header: {
                Text("Agents")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let note = Self.seatsNote(picked: picked.count, available: agents.count) {
                        Text(note).foregroundStyle(Theme.ink)
                    }
                    Text("A message without an @mention goes to all of them.")
                }
            }
            if let problem {
                Section {
                    Text(problem).foregroundStyle(Theme.danger)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isCreating)
    }

    private func row(_ agent: Contact) -> some View {
        let isPicked = picked.contains(agent.id)
        var settled = agent
        settled.activity = .idle
        return Button {
            if isPicked {
                picked.removeAll { $0 == agent.id }
            } else {
                picked.append(agent.id)
            }
        } label: {
            HStack(spacing: 10) {
                AgentAvatar(contact: settled, size: 28)
                Text(agent.name).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isPicked ? Theme.ink : Theme.secondaryInk)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clickable)
        .disabled(!isPicked && picked.count >= Self.seats.upperBound)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    /// A name made from the agents, as "Forge, Atlas & Scribe".
    static func suggestedName(for names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return String(localized: "\(names.dropLast().joined(separator: ", ")) & \(last)")
    }

    /// Why Create is off while too few agents are picked.
    static func seatsNote(picked: Int, available: Int) -> String? {
        if available == 0 {
            return String(localized: "A room needs at least two agents, and this gateway has none yet.")
        }
        if available < seats.lowerBound {
            return String(
                localized:
                    "A room needs at least two agents, and this gateway has one. Make another with New Bot first.")
        }
        switch picked {
        case 0: return String(localized: "Pick two to six agents.")
        case 1: return String(localized: "Pick one more agent.")
        default: return nil
        }
    }

    private var pickedAgents: [Contact] { picked.compactMap { id in agents.first { $0.id == id } } }

    private var suggestion: String { Self.suggestedName(for: pickedAgents.map(\.name)) }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canCreate: Bool {
        !isCreating && Self.seats.contains(picked.count)
    }

    private func submit() {
        guard canCreate else { return }
        let members = pickedAgents
        let name = trimmedName.isEmpty ? suggestion : trimmedName
        isCreating = true
        problem = nil
        Task {
            do {
                let id = try await create(name, members)
                created(id)
                dismiss()
            } catch {
                problem = String(localized: "The room wasn't made. \(AppModel.describe(error))")
                isCreating = false
            }
        }
    }
}

#Preview("New room") {
    NewRoomSheet(
        agents: SampleData.contacts().filter { $0.kind == .agent }, create: { _, _ in "room:new" }, created: { _ in })
}
