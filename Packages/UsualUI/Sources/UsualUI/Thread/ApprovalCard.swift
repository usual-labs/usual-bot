import HermesKit
import SwiftUI

/// The agent asking to run a command, answered right in the chat.
struct ApprovalCard: View {
    let approval: ApprovalPrompt
    let agentName: String
    let answer: (ApprovalPrompt.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("\(agentName) wants to run a command")
                    .scaledFont(size: 13.5, weight: .medium)
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: "terminal")
                    .foregroundStyle(Theme.needsYouInk)
            }
            Text(approval.command)
                .scaledFont(size: 13, design: .monospaced)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 10))
            if !approval.description.isEmpty {
                Text(approval.description)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                // As in a Mac dialog: Deny beside the default, the wider allows apart at the
                // leading end, so Always allow is never one slip from Deny.
                HStack(spacing: 8) {
                    buttons(order.filter(isWider))
                    Spacer(minLength: order.contains(where: isWider) ? 16 : 0)
                    buttons(order.filter { !isWider($0) })
                }
                // Too narrow for a row (iPhone): full-width buttons, Allow once on top and
                // Always allow at the bottom, furthest from it.
                VStack(spacing: 8) { buttons(order.reversed(), fill: true) }
            }
            #if os(iOS)
                // No pointer for a tooltip, so what the wider allows cover is said here.
                if order.contains(where: isWider) {
                    Text(scopes)
                        .scaledFont(size: 12.5)
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            #endif
        }
        .cardSurface()
        .accessibilityLabel(Text("\(agentName) wants to run \(approval.command)"))
    }

    private func buttons(_ choices: [ApprovalPrompt.Choice], fill: Bool = false) -> some View {
        ForEach(choices, id: \.self) { choice in
            Button(title(choice)) { answer(choice) }
                .buttonStyle(CardButtonStyle(primary: choice == .once, fill: fill))
                .help(explanation(choice))
                .accessibilityHint(Text(explanation(choice)))
        }
    }

    /// Leading to trailing in a row: the wider allows, then Deny and Allow once, the default.
    private var order: [ApprovalPrompt.Choice] {
        [.always, .session, .deny, .once].filter(approval.choices.contains)
    }

    /// Allows more than this one command.
    private func isWider(_ choice: ApprovalPrompt.Choice) -> Bool {
        choice == .always || choice == .session
    }

    private func title(_ choice: ApprovalPrompt.Choice) -> LocalizedStringKey {
        switch choice {
        case .once: return "Allow once"
        case .session: return "Allow in this chat"
        case .always: return "Always allow"
        case .deny: return "Deny"
        }
    }

    /// What a choice covers, from Hermes: `session` approves the command's kind for this session,
    /// `always` adds it to the agent's allow list for every session.
    private func explanation(_ choice: ApprovalPrompt.Choice) -> String {
        switch choice {
        case .once: String(localized: "Runs this command this time only.")
        case .session: String(localized: "Allows commands like this one for the rest of this chat.")
        case .always: String(localized: "Allows commands like this one in every chat with \(agentName), from now on.")
        case .deny: String(localized: "Doesn't run it. \(agentName) is told and carries on.")
        }
    }

    private var scopes: String {
        let offered = approval.choices
        if offered.contains(.session), offered.contains(.always) {
            return String(
                localized:
                    "“Allow in this chat” covers commands like this one until the chat ends; “Always allow” covers them in every chat with \(agentName)."
            )
        }
        return offered.contains(.always)
            ? String(localized: "“Always allow” covers commands like this one in every chat with \(agentName).")
            : String(localized: "“Allow in this chat” covers commands like this one until the chat ends.")
    }
}
