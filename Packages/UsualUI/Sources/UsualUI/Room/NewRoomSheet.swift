import HermesKit
import SwiftUI

/// Starts a room: a name and the agents in it. The gateway seats two to six agents.
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
        #if os(macOS)
            VStack(alignment: .leading, spacing: 0) {
                Text("New Room")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                form
                HStack {
                    if isCreating { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Create", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .frame(width: 420, height: 540)
        #else
            NavigationStack {
                form
                    .navigationTitle("New Room")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", role: .cancel) { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            if isCreating {
                                ProgressView()
                            } else {
                                Button("Create", action: submit).disabled(!canCreate)
                            }
                        }
                    }
            }
        #endif
    }

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("Room name"))
                    .onSubmit(submit)
            }
            Section {
                ForEach(agents) { row($0) }
            } header: {
                Text("Agents")
            } footer: {
                Text("Pick two to six. A message without an @mention goes to all of them.")
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
        .buttonStyle(.plain)
        .disabled(!isPicked && picked.count >= Self.seats.upperBound)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canCreate: Bool {
        !isCreating && !trimmedName.isEmpty && Self.seats.contains(picked.count)
    }

    private func submit() {
        guard canCreate else { return }
        let members = picked.compactMap { id in agents.first { $0.id == id } }
        isCreating = true
        problem = nil
        Task {
            do {
                let id = try await create(trimmedName, members)
                created(id)
                dismiss()
            } catch {
                problem = error.localizedDescription
                isCreating = false
            }
        }
    }
}

#Preview("New room") {
    NewRoomSheet(
        agents: SampleData.contacts().filter { $0.kind == .agent }, create: { _, _ in "room:new" }, created: { _ in })
}
