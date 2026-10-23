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
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: "terminal")
                    .foregroundStyle(Theme.needsYouInk)
            }
            Text(approval.command)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 10))
            if !approval.description.isEmpty {
                Text(approval.description)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    buttons
                }
                VStack(alignment: .trailing, spacing: 8) { buttons }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(maxWidth: 540)
        .background(Theme.pane, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(agentName) wants to run \(approval.command)"))
    }

    /// Deny first and the safest allow last, so the primary button sits at the trailing edge.
    @ViewBuilder private var buttons: some View {
        ForEach(order, id: \.self) { choice in
            Button(title(choice)) { answer(choice) }
                .buttonStyle(CardButtonStyle(primary: choice == .once))
        }
    }

    private var order: [ApprovalPrompt.Choice] {
        [.deny, .always, .session, .once].filter(approval.choices.contains)
    }

    private func title(_ choice: ApprovalPrompt.Choice) -> LocalizedStringKey {
        switch choice {
        case .once: return "Allow once"
        case .session: return "Allow in this chat"
        case .always: return "Always allow"
        case .deny: return "Deny"
        }
    }
}
