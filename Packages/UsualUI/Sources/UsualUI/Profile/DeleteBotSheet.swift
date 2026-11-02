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
        #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                content
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView().controlSize(.small)
                        Text("Deleting…").foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .buttonStyle(CardButtonStyle(primary: false))
                        .keyboardShortcut(.cancelAction)
                        .disabled(isDeleting)
                    Button("Delete Bot", role: .destructive, action: submit)
                        .buttonStyle(DeleteButtonStyle())
                        .disabled(!canDelete)
                        .opacity(canDelete ? 1 : 0.4)
                }
            }
            .padding(24)
            .frame(width: 440)
            .presentationBackground(Theme.pane)
        #else
            NavigationStack {
                ScrollView {
                    content.padding(20)
                }
                .navigationTitle("Delete Bot")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }.disabled(isDeleting)
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Button("Delete", role: .destructive, action: submit).disabled(!canDelete)
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete “\(contact.name)”?")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(
                "This deletes \(contact.name)'s Hermes profile from the gateway, with everything in it: its chats, routines, skills, memory, vault, keys and apps. It goes from every app, and it can't be undone."
            )
            if contact.activity != .idle {
                Text("\(contact.name) is in the middle of a reply. Deleting it stops that.")
            }
            if !rooms.isEmpty {
                Text(
                    "It stays listed in \(rooms.map(\.name).formatted(.list(type: .and))), but can't answer there any more. Delete a room to be rid of it."
                )
            }
            TextField("Type \(contact.name) to confirm", text: $typed)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .disabled(isDeleting)
                .accessibilityLabel(Text("Type the Bot's name, \(contact.name), to confirm"))
            if let problem {
                Text(problem).foregroundStyle(Theme.danger)
            }
        }
        .font(.system(size: 13.5))
        .foregroundStyle(Theme.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
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

#if os(macOS)
    /// Red, so it can't pass for the usual primary button.
    private struct DeleteButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Color(light: 0xB42318, dark: 0xD92D20), in: Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Capsule())
                .clickable()
        }
    }
#endif

#Preview("Delete a Bot") {
    let contacts = SampleData.contacts()
    DeleteBotSheet(contact: contacts[0], rooms: contacts.filter { $0.kind != .agent }, delete: {})
}
