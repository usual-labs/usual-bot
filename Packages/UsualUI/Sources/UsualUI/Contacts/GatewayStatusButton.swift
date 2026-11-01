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

    var body: some View {
        Menu {
            Section(gateway.displayName) {
                Text(statusText)
            }
            more()
            Button("Sign Out", role: .destructive, action: signOut)
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
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Gateway \(gateway.displayName), \(statusText)"))
    }

    private var label: String {
        switch link {
        case .online: return gateway.displayName
        case .connecting: return String(localized: "Connecting…")
        case .offline: return String(localized: "Offline, retrying…")
        }
    }

    private var statusText: String {
        switch link {
        case .online(let dialect):
            return dialect == .canonical ? String(localized: "Connected") : String(localized: "Connected (dashboard)")
        case .connecting: return String(localized: "Connecting…")
        case .offline(let reason): return reason
        }
    }

    private var dotColor: Color {
        switch link {
        case .online: return Theme.online
        case .connecting: return Theme.needsYouInk
        case .offline: return Theme.danger
        }
    }
}
