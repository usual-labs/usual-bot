import HermesKit
import SwiftUI

/// What can be done to a Bot as a whole, for the menus and panels that offer it.
struct BotEditing {
    /// Why nothing can be changed right now, such as being offline; `nil` when it can.
    let unavailable: String?
    let takenNames: Set<String>
    let create: (BotName, String?, Data?) async throws -> NewBot
    let rename: (Contact, String) async throws -> Void
    let setPicture: (Contact, Data) async throws -> Void
    let removePicture: (Contact) async throws -> Void
    let delete: (Contact) async throws -> Void
    let canDelete: (Contact) -> Bool
    /// The rooms a Bot is in, to say what deleting it does to them.
    let rooms: (Contact) -> [Contact]
}

extension BotEditing {
    @MainActor init(_ model: AppModel) {
        self.init(
            unavailable: model.botEditingUnavailable, takenNames: model.takenBotNames,
            create: { try await model.createBot($0, description: $1, picture: $2) },
            rename: { try await model.renameBot($0, to: $1) },
            setPicture: { try await model.setBotPicture($0, to: $1) },
            removePicture: { try await model.removeBotPicture($0) },
            delete: { try await model.deleteBot($0) },
            canDelete: { model.canDeleteBot($0) },
            rooms: { model.rooms(including: $0) })
    }

    /// The same, with `deleted` told once a Bot is gone.
    func afterDeleting(_ deleted: @escaping (Contact) -> Void) -> BotEditing {
        let delete = delete
        return BotEditing(
            unavailable: unavailable, takenNames: takenNames, create: create, rename: rename, setPicture: setPicture,
            removePicture: removePicture,
            delete: { contact in
                try await delete(contact)
                deleted(contact)
            }, canDelete: canDelete, rooms: rooms)
    }
}

extension EnvironmentValues {
    /// `nil` where Bots can't be changed.
    @Entry var botEditing: BotEditing?
}

/// A change to a Bot waiting on your input.
enum BotEdit: Equatable {
    case rename(Contact)
    case picture(Contact)
    case removePicture(Contact)
    /// A picture already chosen, such as one dropped on the Bot.
    case usePicture(Contact, Data)
    case delete(Contact)
}

extension View {
    /// Asks for what `edit` needs, then makes the change. Each place that offers these holds its own,
    /// as with rooms. `deleted` hears of a Bot that's gone, to close what showed it.
    func botEditor(_ edit: Binding<BotEdit?>, deleted: @escaping (Contact) -> Void = { _ in }) -> some View {
        modifier(BotEditor(edit: edit, deleted: deleted))
    }
}

/// Rename, Change Picture, Remove Picture and Delete, for a context menu or a `…` button. While
/// nothing can change they're disabled, with the reason below them.
struct BotMenuItems: View {
    let contact: Contact
    let editing: BotEditing
    @Binding var edit: BotEdit?

    var body: some View {
        Group {
            Button("Rename…", systemImage: "pencil") { edit = .rename(contact) }
            Button("Change Picture…", systemImage: "photo") { edit = .picture(contact) }
            if contact.picture != nil {
                Button("Remove Picture", systemImage: "person.crop.circle") { edit = .removePicture(contact) }
            }
        }
        .disabled(editing.unavailable != nil)
        if editing.canDelete(contact) {
            Divider()
            Button("Delete Bot…", systemImage: "trash", role: .destructive) { edit = .delete(contact) }
                .disabled(editing.unavailable != nil)
        }
        if let reason = editing.unavailable {
            Text(reason)
        }
    }
}

private struct BotEditor: ViewModifier {
    @Binding var edit: BotEdit?
    let deleted: (Contact) -> Void
    @Environment(\.botEditing) private var editing
    @State private var name = ""
    @State private var choosingPicture = false
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .alert("Rename Bot", isPresented: asking { if case .rename = $0 { true } else { false } }) {
                TextField("Bot name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { rename() }.disabled(!canRename)
            } message: {
                Text("Only the name changes. Its chats, routines and settings stay as they are.")
            }
            .sheet(isPresented: asking { if case .delete = $0 { true } else { false } }) {
                if case .delete(let contact) = edit, let editing {
                    DeleteBotSheet(contact: contact, rooms: editing.rooms(contact)) {
                        try await editing.delete(contact)
                        deleted(contact)
                    }
                }
            }
            .botPicturePicker(isPresented: $choosingPicture) { data in
                guard case .picture(let contact)? = pictureTarget else { return }
                pictureTarget = nil
                setPicture(data, of: contact)
            }
            .alert(
                "That didn't work", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .onChange(of: edit) {
                switch edit {
                case .rename(let contact): name = contact.name
                case .picture:
                    // The picker shows on its own; the edit is done with once it's asked for.
                    pictureTarget = edit
                    edit = nil
                    choosingPicture = true
                case .removePicture(let contact):
                    edit = nil
                    removePicture(contact)
                case .usePicture(let contact, let data):
                    edit = nil
                    setPicture(data, of: contact)
                default: break
                }
            }
    }

    @State private var pictureTarget: BotEdit?

    private func asking(_ matches: @escaping (BotEdit) -> Bool) -> Binding<Bool> {
        Binding(
            get: { edit.map(matches) ?? false },
            set: { if !$0, edit.map(matches) == true { edit = nil } })
    }

    private var canRename: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= AppModel.longestBotName
    }

    private func setPicture(_ data: Data, of contact: Contact) {
        guard let editing else { return }
        Task {
            do {
                try await editing.setPicture(contact, data)
            } catch {
                problem = String(localized: "\(contact.name)'s picture didn't change. \(AppModel.describe(error))")
            }
        }
    }

    private func removePicture(_ contact: Contact) {
        guard let editing else { return }
        Task {
            do {
                try await editing.removePicture(contact)
            } catch {
                problem = String(localized: "\(contact.name)'s picture is still there. \(AppModel.describe(error))")
            }
        }
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
}
