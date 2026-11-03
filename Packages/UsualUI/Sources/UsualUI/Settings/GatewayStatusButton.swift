import HermesKit
import SwiftUI

/// Which gateway, whether it's reachable, and sign-out: the Mac sidebar's footer, and on iPhone
/// the chat list's top-left button. `more` adds items to its menu, such as the app's Tailscale.
struct GatewayStatusButton<More: View>: View {
    let gateway: GatewayAddress
    let link: AppModel.Link
    /// In the narrow window's rail: the status dot alone.
    var compact = false
    let signOut: () -> Void
    @ViewBuilder let more: () -> More
    @State private var confirmsSignOut = false

    var body: some View {
        Menu {
            Section(gateway.displayName) {
                Text(statusText)
            }
            more()
            Button("Sign Out…", role: .destructive) { confirmsSignOut = true }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                if !compact {
                    Text(label)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                    #if os(macOS)
                        Spacer(minLength: 0)
                    #endif
                }
            }
            #if os(macOS)
                .font(.system(size: 12.5))
                .frame(minWidth: compact ? 44 : nil, minHeight: 28)
            #else
                .font(.system(size: 15))
                .padding(.horizontal, 4)
                // The navigation bar would otherwise squeeze the address down to "…".
                .fixedSize()
            #endif
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .clickable()
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Gateway \(gateway.displayName), \(statusText)"))
        .signOutConfirmation(isPresented: $confirmsSignOut, gateway: gateway, signOut: signOut)
    }

    private var label: String {
        switch link {
        case .online: return gateway.displayName
        case .connecting: return String(localized: "Connecting…")
        case .offline: return String(localized: "Offline, retrying…")
        }
    }

    private var statusText: String { link.statusText }

    private var dotColor: Color { link.dotColor }
}

extension View {
    /// Asks before signing out: it can't be undone, and the chats come back only from the gateway.
    func signOutConfirmation(
        isPresented: Binding<Bool>, gateway: GatewayAddress, signOut: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Sign out of \(gateway.displayName)?", isPresented: isPresented, titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive, action: signOut)
        } message: {
            SignOutNote()
        }
    }
}

/// What signing out does, under the button and in its confirmation.
struct SignOutNote: View {
    var body: some View {
        Text("Signing out removes this gateway’s saved sign-in and cached chats from this device.")
    }
}

extension AppModel.Link {
    /// What the connection is doing, for the status button and the iPhone settings button.
    var statusText: String {
        switch self {
        case .online(let dialect):
            return dialect == .canonical ? String(localized: "Connected") : String(localized: "Connected (dashboard)")
        case .connecting: return String(localized: "Connecting…")
        case .offline(let reason): return reason
        }
    }

    var dotColor: Color {
        switch self {
        case .online: return Theme.online
        case .connecting: return Theme.needsYouInk
        case .offline: return Theme.danger
        }
    }
}

#Preview("Contacts") {
    ContactsSplitView(contacts: SampleData.contacts()) { _ in EmptyView() }
        .frame(width: 1000, height: 640)
}
