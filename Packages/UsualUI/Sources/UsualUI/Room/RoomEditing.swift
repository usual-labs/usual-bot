import HermesKit
import SwiftUI

/// What can be done to a room as a whole, for the menus and panels that offer it.
struct RoomEditing {
    let rename: (Contact, String) async throws -> Void
    let delete: (Contact) async throws -> Void
}

extension EnvironmentValues {
    /// `nil` where rooms can't be changed.
    @Entry var roomEditing: RoomEditing?
}

/// A change to a room waiting on your input.
enum RoomEdit: Equatable {
    case rename(Contact)
    case delete(Contact)
}

extension View {
    /// Asks for what `edit` needs, then makes the change. Each place that offers these holds its
    /// own: on iPhone the room's panel is a sheet, which nothing behind it can present over.
    /// `confirmDelete` replaces deleting right away, for a place that has to go first.
    func roomEditor(_ edit: Binding<RoomEdit?>, confirmDelete: (() -> Void)? = nil) -> some View {
        modifier(RoomEditor(edit: edit, confirmDelete: confirmDelete))
    }
}

private struct RoomEditor: ViewModifier {
    /// As long as the gateway takes.
    private static let longestName = 200

    @Binding var edit: RoomEdit?
    let confirmDelete: (() -> Void)?
    @Environment(\.roomEditing) private var editing
    @State private var name = ""
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .alert("Rename Room", isPresented: asking { if case .rename = $0 { true } else { false } }) {
                TextField("Room name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { rename() }.disabled(!canRename)
            }
            .confirmationDialog(
                "Delete “\(deleting?.name ?? "")”?",
                isPresented: asking { if case .delete = $0 { true } else { false } },
                titleVisibility: .visible, presenting: deleting
            ) { contact in
                Button("Delete Room", role: .destructive) { delete(contact) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(
                    "The room and its messages will be gone for good, and any agent still answering stops. The agents themselves aren't affected."
                )
            }
            .alert(
                "That didn't work", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .onChange(of: edit) {
                if case .rename(let contact) = edit { name = contact.name }
            }
    }

    private func asking(_ matches: @escaping (RoomEdit) -> Bool) -> Binding<Bool> {
        Binding(
            get: { edit.map(matches) ?? false },
            set: { if !$0, edit.map(matches) == true { edit = nil } })
    }

    private var deleting: Contact? {
        if case .delete(let contact) = edit { contact } else { nil }
    }

    private var canRename: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= Self.longestName
    }

    private func rename() {
        guard case .rename(let contact) = edit, let editing, canRename else { return }
        let name = name
        Task {
            do {
                try await editing.rename(contact, name)
            } catch {
                problem = String(localized: "“\(contact.name)” wasn't renamed. \(AppModel.describe(error))")
            }
        }
    }

    private func delete(_ contact: Contact) {
        if let confirmDelete { return confirmDelete() }
        guard let editing else { return }
        Task {
            do {
                try await editing.delete(contact)
            } catch {
                problem = String(localized: "“\(contact.name)” wasn't deleted. \(AppModel.describe(error))")
            }
        }
    }
}

/// A room turn that stopped partway, and can be run again.
struct RetryCard: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("A reply didn't finish")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .foregroundStyle(Theme.needsYouInk)
            }
            Text("The agent may have done part of the work, so trying again can repeat it.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again", action: retry)
                .buttonStyle(.clickable)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44)
        }
        .cardSurface()
    }
}
