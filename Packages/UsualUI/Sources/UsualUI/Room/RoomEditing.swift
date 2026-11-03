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
    /// own, so the list's menu and the room's panel each present from where they are.
    func roomEditor(_ edit: Binding<RoomEdit?>) -> some View {
        modifier(RoomEditor(edit: edit))
    }
}

private struct RoomEditor: ViewModifier {
    /// As long as the gateway takes.
    private static let longestName = 200

    @Binding var edit: RoomEdit?
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
                    "The room and its messages will be gone for good, and any Bot still answering stops. The Bots themselves aren't affected."
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
/// A turn that stopped partway. Dismiss is `groups.stop`, the only way the gateway lets go of
/// it, and that stops every other turn in the room too, so the card says so while there are any.
struct RetryCard: View {
    /// Whose turn it was, when that could be told.
    let agentName: String?
    /// Other turns are running or waiting, and Dismiss would stop them.
    let othersBusy: Bool
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .foregroundStyle(Theme.needsYouInk)
            }
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            // Pills like every other card's, so they read as buttons.
            HStack(spacing: 8) {
                Button("Try Again", action: retry)
                    .buttonStyle(CardButtonStyle(primary: true))
                Button("Dismiss", action: dismiss)
                    .buttonStyle(CardButtonStyle(primary: false))
            }
        }
        .cardSurface()
    }

    private var title: String {
        agentName.map { String(localized: "\($0)'s reply didn't finish") }
            ?? String(localized: "A reply didn't finish")
    }

    private var detail: String {
        let work =
            agentName.map {
                String(localized: "\($0) may have done part of the work, so trying again can repeat it.")
            } ?? String(localized: "The Bot may have done part of the work, so trying again can repeat it.")
        guard othersBusy else { return work }
        return work + " " + String(localized: "Dismiss also stops the replies still running or waiting in this room.")
    }
}
