import HermesKit
import SwiftUI

/// Deleting a Bot loses its whole Hermes profile, so it asks you to type the Bot's name first, as
/// `hermes profile delete` does. Nothing is the default button, so Return can't delete.
struct DeleteBotSheet: View {
    let contact: Contact
    /// The rooms the Bot is in.
    let rooms: [Contact]
    let delete: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var isDeleting = false
    @State private var problem: String?

    var body: some View {
        SheetForm(
            title: Text("Delete “\(contact.name)”?"), cancel: { dismiss() },
            action: SheetAction(
                title: "Delete Bot", role: .destructive, isEnabled: canDelete, isDefault: false, perform: submit),
            busy: isDeleting ? "Deleting…" : nil
        ) {
            form
        }
        #if os(macOS)
            .frame(width: 440, height: 400)
        #else
            .presentationDetents([.medium, .large])
        #endif
    }

    private var form: some View {
        Form {
            Section {
                Text(
                    "This deletes \(contact.name)'s Hermes profile from the gateway, with everything in it: its chats, routines, skills, memory, vault, keys and apps. It goes from every app, and it can't be undone."
                )
                if let note = Self.activityNote(for: contact) {
                    Text(note)
                }
                if !rooms.isEmpty {
                    Text(
                        "It stays listed in \(rooms.map(\.name).formatted(.list(type: .and))), but can't answer there any more. Delete a room to be rid of it."
                    )
                }
            }
            .foregroundStyle(.secondary)
            Section {
                TextField("Name", text: $typed, prompt: Text(contact.name))
                    .textInputTint()
                    .labelsHidden()
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .disabled(isDeleting)
                    .accessibilityLabel(Text("Type the Bot's name, \(contact.name), to confirm"))
            } header: {
                Text("Type \(contact.name) to confirm")
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(Theme.danger)
                }
            }
        }
    }

    /// What deleting it now would cut short, if anything.
    static func activityNote(for contact: Contact) -> String? {
        switch contact.activity {
        case .idle: nil
        case .working: String(localized: "\(contact.name) is in the middle of a reply. Deleting it stops that.")
        case .needsYou: String(localized: "\(contact.name) is waiting on you. Deleting it drops that request.")
        }
    }

    private var canDelete: Bool {
        !isDeleting
            && typed.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(contact.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func submit() {
        guard canDelete else { return }
        isDeleting = true
        problem = nil
        Task {
            do {
                try await delete()
                dismiss()
            } catch {
                problem = String(localized: "\(contact.name) wasn't deleted. \(AppModel.describe(error))")
                isDeleting = false
            }
        }
    }
}

#Preview("Delete a Bot") {
    let contacts = SampleData.contacts()
    DeleteBotSheet(contact: contacts[0], rooms: contacts.filter { $0.kind != .agent }, delete: {})
}
