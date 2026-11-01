import SwiftUI

/// A masked field for a password, master password, card detail or code. Its text is never shown
/// and stays out of the system's autocorrection.
struct VaultSecureField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var isCode = false

    var body: some View {
        SecureField(title, text: $text)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .privacySensitive()
            #if os(iOS)
                .textContentType(isCode ? .oneTimeCode : .password)
                .textInputAutocapitalization(.never)
            #endif
            .vaultFieldStyle()
    }
}

/// A plain field in the same style, for what isn't secret on screen: a label, a site, an email.
struct VaultTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    /// Web addresses and usernames: no capitals or corrections.
    var isLiteral = false

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .autocorrectionDisabled(isLiteral)
            #if os(iOS)
                .textInputAutocapitalization(isLiteral ? .never : .sentences)
            #endif
            .vaultFieldStyle()
    }
}

extension View {
    fileprivate func vaultFieldStyle() -> some View {
        font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Theme.pane, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
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
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.needsYouInk)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.open")
                    .foregroundStyle(Theme.needsYouInk)
            }
            Toggle("Send it anyway", isOn: $isAllowed)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
        }
        .padding(10)
        .background(Theme.needsYouFill, in: RoundedRectangle(cornerRadius: 10))
    }
}
