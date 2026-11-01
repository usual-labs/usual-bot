import HermesKit
import SwiftUI

/// The gateway asking for a secret or a sudo password, typed into a masked field in the chat.
/// Everything it sends shows as plain text, and what you type stays only until you answer.
struct SecretCard: View {
    let prompt: SecretPrompt
    let agentName: String
    /// The gateway is on plain http off this device, so the answer can be read on the network.
    let isUnencrypted: Bool
    let answer: (String) -> Void
    let skip: () -> Void

    @State private var value = ""

    /// The card's heading, also its row in the ⌥Space panel.
    static func title(_ prompt: SecretPrompt, agentName: String) -> String {
        switch prompt.kind {
        case .secret: String(localized: "\(agentName) needs a secret")
        case .sudo: String(localized: "\(agentName) needs your sudo password")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: Self.title(prompt, agentName: agentName))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(Theme.needsYouInk)
            }
            details
            SecureField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .autocorrectionDisabled()
                .privacySensitive()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.pane, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            if isUnencrypted {
                Label(
                    "This gateway uses plain http, so others on your network could read what you send.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 13))
                .foregroundStyle(Theme.needsYouInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Skip") {
                    value = ""
                    skip()
                }
                .buttonStyle(CardButtonStyle(primary: false))
                Button(isUnencrypted ? "Send Unencrypted" : "Send", action: send)
                    .buttonStyle(CardButtonStyle(primary: true))
                    .disabled(value.isEmpty)
                    .opacity(value.isEmpty ? 0.4 : 1)
            }
        }
        .cardSurface()
        .onDisappear { value = "" }
    }

    /// The gateway's own words, never read as Markdown or links.
    @ViewBuilder private var details: some View {
        switch prompt.kind {
        case .secret(let name, let message):
            code(name)
            if !message.isEmpty {
                Text(verbatim: message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .sudo(let command):
            if !command.isEmpty { code(command) }
        }
    }

    private func code(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 10))
    }

    private var icon: String {
        switch prompt.kind {
        case .secret: "key"
        case .sudo: "lock"
        }
    }

    private var placeholder: LocalizedStringKey {
        switch prompt.kind {
        case .secret: "Secret"
        case .sudo: "Password"
        }
    }

    private func send() {
        guard !value.isEmpty else { return }
        let entered = value
        value = ""
        answer(entered)
    }
}
