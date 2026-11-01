import HermesKit
import SwiftUI

/// The sidebar footer: which gateway, whether it's reachable, and sign-out.
struct GatewayStatusButton: View {
    let gateway: GatewayAddress
    let link: AppModel.Link
    /// In the narrow window's rail: the status dot alone.
    var compact = false
    let signOut: () -> Void

    var body: some View {
        Menu {
            Section(gateway.displayName) {
                Text(statusText)
            }
            Button("Sign Out", role: .destructive, action: signOut)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                if !compact {
                    Text(label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            #if os(macOS)
                .frame(minWidth: compact ? 44 : nil, minHeight: 28)
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

#Preview("Contacts") {
    ContactsSplitView(contacts: SampleData.contacts()) { _ in EmptyView() }
        .frame(width: 1000, height: 640)
}
