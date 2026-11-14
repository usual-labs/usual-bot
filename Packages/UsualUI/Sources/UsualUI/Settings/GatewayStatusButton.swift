import HermesKit
import SwiftUI

/// Which gateway, whether it's reachable, switching to the other one, and sign-out: the Mac
/// sidebar's footer. `more` adds items to its menu, such as the app's Tailscale.
struct GatewayStatusButton<More: View>: View {
    let model: AppModel
    let gateway: GatewayAddress
    @ViewBuilder let more: () -> More
    @State private var confirmsSignOut = false

    var body: some View {
        Menu {
            Section(name) {
                Text(statusText)
            }
            GatewayChoices(model: model)
            more()
            Button("Sign Out…", role: .destructive) { confirmsSignOut = true }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(label)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                if hasNews { NewsDot() }
                #if os(macOS)
                    Spacer(minLength: 0)
                #endif
            }
            #if os(macOS)
                .scaledFont(size: 12.5)
                .frame(minHeight: 28)
            #else
                .scaledFont(size: 15)
                .padding(.horizontal, 4)
                // The navigation bar would otherwise squeeze the address down to "…".
                .fixedSize()
            #endif
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        // Plain: a Mac menu in a system style flattens its label to a title, losing the dot.
        .buttonStyle(.plain)
        .clickable()
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Gateway \(name), \(statusText)"))
        .accessibilityValue(hasNews ? Text("New notifications on your other gateway") : Text(""))
        .signOutConfirmation(isPresented: $confirmsSignOut, name: name, signOut: model.signOut)
    }

    private var link: AppModel.Link { model.link }
    private var name: String { model.activeGateway?.displayName ?? gateway.displayName }
    private var hasNews: Bool { !model.gatewaysWithNews.isEmpty }

    private var label: String {
        switch link {
        case .online: return name
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
        isPresented: Binding<Bool>, name: String, signOut: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Sign out of \(name)?", isPresented: isPresented, titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive, action: signOut)
        } message: {
            SignOutNote()
        }
    }
}

/// Each gateway, a check on the one in use: choosing another switches to it. Then Add Gateway,
/// until there are as many as the app takes.
struct GatewayChoices: View {
    let model: AppModel

    var body: some View {
        Section("Gateways") {
            ForEach(model.gateways) { gateway in
                Button {
                    model.switchTo(gateway.id)
                } label: {
                    if gateway.id == model.activeGateway?.id {
                        Label(gateway.displayName, systemImage: "checkmark")
                    } else if model.gatewaysWithNews.contains(gateway.id) {
                        Text(gateway.displayName)
                        Text("New notifications")
                    } else {
                        Text(gateway.displayName)
                    }
                }
            }
            Button("Add Gateway…", systemImage: "plus") { model.addGateway() }
                .disabled(!model.canAddGateway)
            if !model.canAddGateway {
                Text("Usual Bot connects to two gateways at most.")
            }
        }
    }
}

/// Another gateway has notifications waiting.
struct NewsDot: View {
    var body: some View {
        Circle()
            .fill(Theme.primary)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
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
            // The dashboard holds Bot Chats itself, so the gateway can't deliver into them.
            return dialect == .canonical
                ? String(localized: "Connected")
                : String(
                    localized: """
                        Connected to the dashboard, so routines and other Bots can't post in chats. \
                        Connect to the gateway's web app instead.
                        """)
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

    /// The chat list with nothing in it. Offline, the app retries by itself, but say what to
    /// check rather than "Connecting…", which reads as if it's about to work.
    var emptyListText: String {
        switch self {
        case .online: String(localized: "No Bots on this gateway yet.")
        case .connecting: String(localized: "Connecting…")
        case .offline: String(localized: "Can't reach your gateway. Check your connection or Tailscale.")
        }
    }

    /// Offline, the empty list offers to reconnect now instead of waiting for the next retry.
    var offersTryAgain: Bool {
        if case .offline = self { return true }
        return false
    }
}

#Preview("Contacts") {
    ContactsSplitView(contacts: SampleData.contacts()) { _ in EmptyView() }
        .frame(width: 1000, height: 640)
}
