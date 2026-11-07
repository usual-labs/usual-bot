import HermesKit
import SwiftUI

/// Bots hidden from the sidebar, here or in the official app, each with a way back. Shown even
/// with none, so you can find where they go.
struct HiddenBotsSection: View {
    let model: AppModel

    @State private var showing: Set<Contact.ID> = []
    @State private var problem: String?

    var body: some View {
        let bots = model.hiddenBots.sorted(by: Contact.rosterOrder)
        Section {
            if bots.isEmpty {
                Text("No hidden Bots.").foregroundStyle(Theme.secondaryInk)
            }
            ForEach(bots) { bot in
                HStack(spacing: 10) {
                    AgentAvatar(contact: bot.with(activity: .idle), size: 26)
                    Text(bot.name).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    if showing.contains(bot.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Show") { show(bot) }
                            .disabled(model.botEditingUnavailable != nil)
                            .accessibilityLabel(Text("Show \(bot.name)"))
                            #if os(iOS)
                                // Only the word, not the whole row, shows the Bot.
                                .buttonStyle(.borderless)
                            #endif
                    }
                }
            }
        } header: {
            Text("Hidden Bots")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !bots.isEmpty, let reason = model.botEditingUnavailable { Text(reason) }
                #if os(macOS)
                    Text(
                        "Hidden Bots keep working: their routines run and they reply in rooms, but they don’t notify you. To hide one, use its menu in the sidebar."
                    )
                #else
                    Text(
                        "Hidden Bots keep working: their routines run and they reply in rooms, but they don’t notify you. To hide one, touch and hold it in Chats."
                    )
                #endif
            }
        }
        .environment(\.botPictures, model.pictures)
        .alert(
            "That didn't work", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private func show(_ bot: Contact) {
        showing.insert(bot.id)
        Task {
            defer { showing.remove(bot.id) }
            do {
                try await model.showBot(bot)
            } catch {
                problem = String(localized: "\(bot.name) is still hidden. \(AppModel.describe(error))")
            }
        }
    }
}
