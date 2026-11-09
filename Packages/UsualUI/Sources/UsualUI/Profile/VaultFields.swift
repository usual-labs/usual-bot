import SwiftUI

/// A masked field for a password, master password, card detail or code. Its text is never shown
/// and stays out of the system's autocorrection. The field's style comes from where it is: a form's
/// row, or `.roundedBorder` on a card.
struct VaultSecureField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var isCode = false

    var body: some View {
        SecureField(title, text: $text, prompt: Text(title))
            .autocorrectionDisabled()
            .privacySensitive()
            #if os(iOS)
                .textContentType(isCode ? .oneTimeCode : .password)
                .textInputAutocapitalization(.never)
            #endif
            .vaultFieldStyle()
    }
}

/// A plain field to go with it, for what isn't secret on screen: a label, a site, an email.
struct VaultTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    /// Web addresses and usernames: no capitals or corrections.
    var isLiteral = false

    var body: some View {
        TextField(title, text: $text, prompt: Text(title))
            .autocorrectionDisabled(isLiteral)
            #if os(iOS)
                .textInputAutocapitalization(isLiteral ? .never : .sentences)
            #endif
            .vaultFieldStyle()
    }
}

extension View {
    /// The title is the field's prompt and its VoiceOver label, never a label beside it: a Mac form
    /// row would show it twice.
    fileprivate func vaultFieldStyle() -> some View {
        scaledFont(size: 14).labelsHidden().textInputTint()
    }
}

/// Shown on a plain `http` address to another machine: says what's at stake and takes your say-so
/// for this one send. It starts off every time; nothing remembers it.
struct UnencryptedConsent: View {
    @Binding var isAllowed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(
                    "This gateway uses plain http, so this could be read on the network. It's safe only inside a tunnel such as Tailscale."
                )
                .scaledFont(size: 12.5)
                .foregroundStyle(Theme.needsYouInk)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.open")
                    .foregroundStyle(Theme.needsYouInk)
            }
            Toggle("Send it anyway", isOn: $isAllowed)
                .toggleStyle(.systemSwitch)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.ink)
        }
        .padding(10)
        .background(Theme.needsYouFill, in: RoundedRectangle(cornerRadius: 10))
    }
}
