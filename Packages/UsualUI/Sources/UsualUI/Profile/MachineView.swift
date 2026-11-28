import HermesKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// What the Bot runs on: its profile and model, and the gateway.
struct MachineView: View {
    let details: AgentDetails?
    let gateway: GatewayAddress
    let link: AppModel.Link
    let gatewayDetails: GatewayDetails?
    let load: () async -> Void
    var top: AnyView?

    var body: some View {
        ProfileForm(top: top) {
            Section {
                row("Profile", details?.profile)
                row("Model", details?.model)
                row("Provider", details?.provider)
                row("Skills", details?.skillCount.map { String($0) })
            } header: {
                ProfileSectionHeader("Bot")
            }
            Section {
                row("Address", gateway.displayName)
                row("Version", gatewayDetails?.version)
                row("Status", statusText)
                row("Signed in as", gatewayDetails?.account)
            } header: {
                ProfileSectionHeader("Gateway")
            }
            #if os(macOS)
                if let settings = Self.hermesSettings {
                    Section {
                        Button("Open Hermes for advanced settings") { NSWorkspace.shared.open(settings) }
                            .buttonStyle(.clickable(.bordered))
                    }
                }
            #endif
        }
        .task { await load() }
    }

    private var statusText: String {
        switch link {
        case .connecting: return String(localized: "Connecting…")
        case .offline: return String(localized: "Offline")
        case .online:
            return gatewayDetails?.isHealthy == false
                ? String(localized: "Connected, some parts need attention")
                : String(localized: "Connected")
        }
    }

    @ViewBuilder private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) {
                Text(value).textSelection(.enabled)
            }
        }
    }

    #if os(macOS)
        /// The official Hermes app's settings, when it's installed on this Mac.
        private static var hermesSettings: URL? {
            guard let url = URL(string: "hermes://open/settings"),
                NSWorkspace.shared.urlForApplication(toOpen: url) != nil
            else { return nil }
            return url
        }
    #endif
}
