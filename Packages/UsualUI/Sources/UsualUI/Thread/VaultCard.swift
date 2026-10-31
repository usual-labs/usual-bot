import HermesKit
import SwiftUI

/// A chat's waiting vault prompts, in the transcript or the quick panel.
struct VaultCards: View {
    let thread: ChatThread
    let agentName: String

    var body: some View {
        ForEach(thread.vaultPrompts) { prompt in
            VaultCard(
                prompt: prompt, agentName: agentName, isUnencrypted: thread.vaultAnswersAreUnencrypted,
                answer: {
                    thread.answer(prompt, secret: $0, identifier: $1, allowingUnencrypted: $2)
                }, skip: { thread.skip(prompt) })
        }
    }
}

/// The agent needs a master password, a login or a one-time code, answered right in the chat. What
/// you type goes to the vault or the page, not to the agent's model. Withdrawing the prompt takes
/// this view, and with it what you typed, away.
struct VaultCard: View {
    let prompt: VaultPrompt
    let agentName: String
    let isUnencrypted: Bool
    /// Sends the secret, the identifier for a login, and your say-so on an unencrypted address.
    let answer: (String, String?, Bool) -> Bool
    let skip: () -> Void

    @State private var identifier = ""
    @State private var secret = ""
    @State private var allowsUnencrypted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: "lock")
                    .foregroundStyle(Theme.needsYouInk)
            }
            if let site {
                Text(site)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 10))
            }
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            fields
            if isUnencrypted { UnencryptedConsent(isAllowed: $allowsUnencrypted) }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(skipTitle) {
                    clear()
                    skip()
                }
                .buttonStyle(CardButtonStyle(primary: false))
                Button("Send", action: send)
                    .buttonStyle(CardButtonStyle(primary: true))
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.4)
            }
        }
        .padding(14)
        .frame(maxWidth: 540)
        .background(Theme.pane, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var fields: some View {
        switch prompt.kind {
        case .unlock:
            VaultSecureField(title: "Master password", text: $secret)
        case .saveLogin:
            VaultTextField(title: "Email or username", text: $identifier, isLiteral: true)
            VaultSecureField(title: "Password", text: $secret)
        case .code:
            VaultSecureField(title: "Code", text: $secret, isCode: true)
        }
    }

    private var isLogin: Bool {
        if case .saveLogin = prompt.kind { return true }
        return false
    }

    private var canSend: Bool {
        !secret.isEmpty && (!isLogin || !identifier.isEmpty) && (!isUnencrypted || allowsUnencrypted)
    }

    private func send() {
        guard answer(secret, isLogin ? identifier : nil, allowsUnencrypted) else { return }
        clear()
    }

    private func clear() {
        identifier = ""
        secret = ""
        allowsUnencrypted = false
    }

    private var title: LocalizedStringKey {
        switch prompt.kind {
        case .unlock(_, let name): return "\(agentName) needs \(name) unlocked"
        case .saveLogin: return "\(agentName) needs a login to save"
        case .code: return "\(agentName) needs a one-time code"
        }
    }

    /// Shown in full, so you can check the address before you type anything for it.
    private var site: String? {
        switch prompt.kind {
        case .unlock: return nil
        case .saveLogin(let origin, _): return origin
        case .code(let site, _): return site
        }
    }

    private var note: LocalizedStringKey {
        switch prompt.kind {
        case .unlock: return "It stays unlocked for this session. \(agentName) never sees the master password."
        case .saveLogin: return "It's saved in the vault and filled in here. \(agentName) never sees the password."
        case .code(_, let hint):
            if let hint { return "\(hint)" }
            return "The code you got by phone, email or app goes straight into the page."
        }
    }

    private var skipTitle: LocalizedStringKey {
        if case .unlock = prompt.kind { return "Keep Locked" }
        return "Skip"
    }
}
