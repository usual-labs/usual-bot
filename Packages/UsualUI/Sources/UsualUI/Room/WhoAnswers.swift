import HermesKit
import SwiftUI

extension RoomRouting {
    /// The choice, as New Room and Room Settings list it.
    var title: String {
        switch self {
        case .everyone: String(localized: "Everyone answers")
        case .lead: String(localized: "A lead picks")
        case .auto: String(localized: "The room picks")
        }
    }

    /// What the choice does to a message that names nobody.
    var explanation: String {
        let rule =
            switch self {
            case .everyone: String(localized: "Every Bot answers a message that doesn't @mention anyone.")
            case .lead:
                String(
                    localized:
                        "The lead reads a message that doesn't @mention anyone and picks who answers it, itself included."
                )
            case .auto:
                String(
                    localized:
                        "Hermes picks who answers a message that doesn't @mention anyone, with one short model call on the gateway. If it can't pick, everyone answers."
                )
            }
        guard self != .everyone else { return rule }
        return rule + " " + String(localized: "An @mention still goes straight to that Bot.")
    }
}

extension RoomSettings {
    /// Who answers in this room, in a line. `lead` is the lead's name.
    func whoAnswers(lead: String?) -> String {
        switch routing {
        case .everyone: String(localized: "Everyone answers")
        case .auto: String(localized: "The room picks who answers")
        case .lead:
            lead.map { String(localized: "\($0) picks who answers") } ?? String(localized: "A lead picks who answers")
        }
    }
}

/// A room member that can lead, by its member ID.
struct LeadChoice: Identifiable, Hashable {
    let id: String
    let name: String

    /// The lead to show and save: the chosen one while it's still a member, else the first.
    static func resolved(_ lead: String?, among members: [LeadChoice]) -> String? {
        members.contains { $0.id == lead } ? lead : members.first?.id
    }
}

/// The form section that chooses who answers, and the lead when a lead does.
struct WhoAnswersSection: View {
    /// The choices the gateway takes.
    let modes: [RoomRouting]
    let members: [LeadChoice]
    @Binding var routing: RoomRouting
    @Binding var lead: String?

    var body: some View {
        Section {
            Picker("Who answers", selection: $routing) {
                ForEach(modes, id: \.self) { Text($0.title).tag($0) }
            }
            if routing == .lead {
                if members.isEmpty {
                    Text("Pick the Bots first, then the one that leads.")
                        .foregroundStyle(Theme.secondaryInk)
                } else {
                    Picker(
                        "Lead",
                        selection: Binding(
                            get: { LeadChoice.resolved(lead, among: members) }, set: { lead = $0 })
                    ) {
                        ForEach(members) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
        } footer: {
            Text(routing.explanation)
        }
    }
}

/// Changes who answers in a room, its purpose and its notes. Hermes saves the four together.
struct RoomSettingsSheet: View {
    let current: RoomSettings
    /// Empty where the gateway's rooms have a purpose and notes but no routing.
    let modes: [RoomRouting]
    let members: [LeadChoice]
    /// Why nothing can be saved right now, such as being offline.
    let unavailable: String?
    let save: (RoomSettings) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: RoomSettings
    @State private var lead: String?
    @State private var isSaving = false
    @State private var problem: String?

    init(
        current: RoomSettings, modes: [RoomRouting], members: [LeadChoice], unavailable: String?,
        save: @escaping (RoomSettings) async throws -> Void
    ) {
        self.current = current
        self.modes = modes
        self.members = members
        self.unavailable = unavailable
        self.save = save
        _draft = State(initialValue: current)
        _lead = State(initialValue: current.leadID)
    }

    var body: some View {
        SheetForm(
            title: Text("Room Settings"), cancel: { dismiss() },
            action: SheetAction(title: "Save", isEnabled: canSave, perform: submit),
            busy: isSaving ? "Saving…" : nil
        ) {
            Form {
                if let unavailable {
                    Section { Text(unavailable).foregroundStyle(Theme.ink) }
                }
                Group {
                    if !modes.isEmpty {
                        WhoAnswersSection(modes: modes, members: members, routing: $draft.routing, lead: $lead)
                    }
                    Section {
                        TextField(
                            "Purpose", text: $draft.purpose, prompt: Text("What this room is for, in one line")
                        )
                        .textInputTint()
                        .labelsHidden()
                    } header: {
                        Text("Purpose")
                    }
                    Section {
                        TextEditor(text: $draft.notes)
                            .textInputTint()
                            .scaledFont(size: 14)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 96)
                            .accessibilityLabel(Text("Notes"))
                    } header: {
                        Text("Notes")
                    } footer: {
                        Text(
                            "Facts every Bot should keep in mind. Each Bot gets the purpose and the notes with every message, starting with the next one."
                        )
                    }
                }
                .disabled(unavailable != nil)
                if let problem = problem ?? changed.problem {
                    Section { Text(problem).foregroundStyle(Theme.danger) }
                }
            }
            .disabled(isSaving)
        }
        #if os(macOS)
            .frame(width: 440, height: 520)
        #endif
    }

    /// The draft as it would be saved.
    private var changed: RoomSettings {
        RoomSettings(
            purpose: draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines), routing: draft.routing,
            leadID: LeadChoice.resolved(lead, among: members))
    }

    private var canSave: Bool {
        !isSaving && unavailable == nil && changed != current && changed.problem == nil
    }

    private func submit() {
        guard canSave else { return }
        let settings = changed
        isSaving = true
        problem = nil
        Task {
            do {
                try await save(settings)
                dismiss()
            } catch {
                problem = String(localized: "The room's settings weren't saved. \(AppModel.describe(error))")
                isSaving = false
            }
        }
    }
}

#Preview("Room settings") {
    RoomSettingsSheet(
        current: RoomSettings(purpose: "Ship the Thursday launch", routing: .lead, leadID: "forge"),
        modes: RoomRouting.allCases,
        members: [LeadChoice(id: "forge", name: "Forge"), LeadChoice(id: "atlas", name: "Atlas")], unavailable: nil,
        save: { _ in })
}
