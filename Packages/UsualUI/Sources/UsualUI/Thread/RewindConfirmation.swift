import HermesKit
import SwiftUI

/// A change that takes messages out of a chat for good, waiting for your yes: an edit of one of
/// your messages, or the last reply asked again. Asked only when more than the last exchange goes,
/// or when the Bot acted in what goes (`ChatThread.RewindCost.needsConfirmation`).
struct RewindRequest: Equatable {
    enum Kind: Equatable {
        case edit(TranscriptItem, text: String)
        case tryAgain
    }

    let kind: Kind
    let cost: ChatThread.RewindCost

    var title: String {
        switch kind {
        case .tryAgain: String(localized: "Try this reply again?")
        case .edit where !cost.reachesBack: String(localized: "Replace your last message?")
        case .edit where cost.messages == 1: String(localized: "Replace this message and remove the one after it?")
        case .edit: String(localized: "Replace this message and remove the \(cost.messages) after it?")
        }
    }

    /// What goes, that it can't come back, and what a rewind doesn't reach: the Bot's own actions.
    func message(agentName: String) -> String {
        var lines: [String] = []
        switch kind {
        case .tryAgain:
            lines.append(String(localized: "\(agentName)'s reply is removed, and it answers your message again."))
        case .edit where !cost.reachesBack:
            lines.append(String(localized: "\(agentName)'s reply is removed, and it answers your new message."))
        case .edit:
            lines.append(
                String(
                    localized:
                        "The chat goes back to this message, and \(agentName) answers your new one. What's removed can't be brought back."
                ))
        }
        if cost.fromHermes == 1 {
            lines.append(String(localized: "One of them came from Hermes itself, such as a routine's result."))
        } else if cost.fromHermes > 1 {
            lines.append(
                String(localized: "\(cost.fromHermes) of them came from Hermes itself, such as a routine's result."))
        }
        if cost.steps > 0 {
            lines.append(
                String(
                    localized:
                        "\(agentName) already acted on what's removed, such as running commands or changing files. That stays done, and it may do it again."
                ))
        } else {
            lines.append(
                String(
                    localized:
                        "Anything \(agentName) already did stays done: files it changed, commands it ran, messages it sent."
                ))
        }
        return lines.joined(separator: "\n\n")
    }

    var confirmLabel: String {
        switch kind {
        case .tryAgain: String(localized: "Try Again")
        case .edit where cost.reachesBack: String(localized: "Replace and Remove")
        case .edit: String(localized: "Replace")
        }
    }

    var cancelLabel: String {
        switch kind {
        case .tryAgain: String(localized: "Cancel")
        case .edit: String(localized: "Keep Editing")
        }
    }

    /// What the message box says while you edit `item`, so what sending removes is in view before
    /// you send.
    static func editingLabel(for cost: ChatThread.RewindCost?) -> String {
        guard let cost, cost.reachesBack else { return String(localized: "Editing your last message") }
        return cost.messages == 1
            ? String(localized: "Editing a message. The one after it goes too.")
            : String(localized: "Editing a message. The \(cost.messages) after it go too.")
    }
}

extension View {
    /// Asks before a rewind that needs asking.
    func rewindConfirmation(
        _ request: Binding<RewindRequest?>, agentName: String, confirm: @escaping (RewindRequest) -> Void
    ) -> some View {
        // An alert, not a confirmation dialog: on iPhone that one is a popover from the chat, too
        // small for what this has to say.
        alert(
            request.wrappedValue?.title ?? "",
            isPresented: Binding(get: { request.wrappedValue != nil }, set: { if !$0 { request.wrappedValue = nil } }),
            presenting: request.wrappedValue
        ) { asked in
            Button(asked.confirmLabel, role: .destructive) { confirm(asked) }
            Button(asked.cancelLabel, role: .cancel) {}
        } message: { asked in
            Text(asked.message(agentName: agentName))
        }
    }
}

extension EnvironmentValues {
    /// The message being edited: what follows it is shown faded, as sending the edit removes it.
    @Entry var editingFrom: TranscriptItem.ID?
}
