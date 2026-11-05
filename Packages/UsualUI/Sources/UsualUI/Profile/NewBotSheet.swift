import HermesKit
import SwiftUI

/// Makes a Bot: what Grok's Create New Bot asks for, a name and a look, and what it's for if you
/// like. Its model, skills and tools start from Hermes's defaults and are changed in the Hermes app.
struct NewBotSheet: View {
    let editing: BotEditing
    /// Told the new Bot's contact ID, to open it.
    let created: (Contact.ID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var about = ""
    /// The picture as picked, and as it will look: the middle square.
    @State private var picture: (file: Data, square: Data)?
    @State private var choosingPicture = false
    @State private var isDropTarget = false
    @State private var isCreating = false
    @State private var problem: String?
    /// Made, with something to say before it opens.
    @State private var made: (bot: NewBot, note: String)?

    private static let previewID = "new-bot-preview"

    var body: some View {
        SheetForm(
            title: Text("New Bot"), cancel: made == nil ? { dismiss() } : nil,
            action: made != nil
                ? SheetAction(title: "Open Chat", perform: finish)
                : SheetAction(title: "Create", isEnabled: canCreate, perform: submit),
            busy: isCreating ? "Creating…" : nil
        ) {
            form
        }
        #if os(macOS)
            .frame(width: 420, height: 560)
        #endif
    }

    private var form: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    preview
                    HStack(spacing: 8) {
                        Button(picture == nil ? "Choose Picture…" : "Change Picture…") { choosingPicture = true }
                        if picture != nil {
                            Button("Remove", role: .destructive) { picture = nil }
                        }
                    }
                    .buttonStyle(.clickable(.bordered))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Without a picture it gets one of the app's faces.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            Section {
                TextField("Name", text: $name, prompt: Text("Bot name"))
                    .onSubmit(submit)
                TextField("What it's for", text: $about, prompt: Text("What it's for (optional)"), axis: .vertical)
                    .lineLimit(1...4)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let nameProblem, !name.isEmpty {
                        Text(nameProblem).foregroundStyle(Theme.danger)
                    }
                    Text("It starts with Hermes's own model, skills and tools. Change them in the Hermes app.")
                }
            }
            if let note = made?.note {
                Section {
                    Text(note).foregroundStyle(Theme.ink)
                }
            }
            if let problem {
                Section {
                    Text(problem).foregroundStyle(Theme.danger)
                }
            }
            if let reason = editing.unavailable, made == nil {
                Section {
                    Text(reason).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
        .disabled(isCreating || made != nil)
        .botPicturePicker(isPresented: $choosingPicture, picked: use)
    }

    /// The face it would get, or the picture you chose, cropped as it will be.
    private var preview: some View {
        let botName = BotName(name)
        let seed = botName.profile.isEmpty ? "new" : botName.profile
        return ZStack {
            if let square = picture?.square, let image = AvatarArt.picture(square, for: Self.previewID) {
                image.resizable().interpolation(.high).scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
            } else {
                AgentAvatar(contact: Contact(id: seed, name: botName.title), size: 88)
            }
        }
        .overlay {
            if isDropTarget {
                Circle().strokeBorder(Theme.ink.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .botPictureDrop(isTargeted: $isDropTarget, picked: use)
        .accessibilityElement()
        .accessibilityLabel(picture == nil ? Text("Bot face") : Text("Chosen picture"))
        .accessibilityAddTraits(.isImage)
    }

    private func use(_ data: Data) {
        guard let square = BotPictureFile.prepare(data) else {
            problem = String(localized: "That file isn't a picture Usual Bot can read.")
            return
        }
        problem = nil
        picture = (data, square)
    }

    private var nameProblem: String? {
        BotName(name).problem(taken: editing.takenNames)
    }

    private var canCreate: Bool {
        !isCreating && made == nil && nameProblem == nil && editing.unavailable == nil
            && name.trimmingCharacters(in: .whitespacesAndNewlines).count <= AppModel.longestBotName
    }

    private func submit() {
        guard canCreate else { return }
        isCreating = true
        problem = nil
        let description = about.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let bot = try await editing.create(
                    BotName(name), description.isEmpty ? nil : description, picture?.square)
                isCreating = false
                if let note = Self.note(for: bot, named: BotName(name).title) {
                    made = (bot, note)
                } else {
                    created(bot.id)
                    dismiss()
                }
            } catch {
                problem = String(localized: "The Bot wasn't made. \(AppModel.describe(error))")
                isCreating = false
            }
        }
    }

    private func finish() {
        if let made { created(made.bot.id) }
        dismiss()
    }

    private static func note(for bot: NewBot, named name: String) -> String? {
        var notes: [String] = []
        if !bot.canReply {
            notes.append(
                String(
                    localized:
                        "\(name) is ready, but it can't reply yet: Hermes found no model it can use. Choose one for it in the Hermes app."
                ))
        }
        if bot.pictureFailed {
            notes.append(
                String(localized: "\(name) is ready, but its picture didn't save. Try again from its profile."))
        }
        return notes.isEmpty ? nil : notes.joined(separator: "\n\n")
    }
}

#Preview("New Bot") {
    NewBotSheet(
        editing: BotEditing(
            unavailable: nil, takenNames: ["scout"], create: { name, _, _ in NewBot(id: name.profile) },
            rename: { _, _ in }, setPicture: { _, _ in }, removePicture: { _ in }, delete: { _ in },
            canDelete: { _ in true }, rooms: { _ in [] }),
        created: { _ in })
}
