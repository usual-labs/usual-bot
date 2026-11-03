import HermesKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// The agent's card beside the chat: who it is, its routines, skills, apps and vault, and the machine it runs on.
/// A trailing column with tabs on the Mac; on iPhone a sheet of rows that open each page, as in
/// Grok's phone app.
struct ProfilePanel: View {
    enum Tab: Hashable, CaseIterable {
        case routines, skills, apps, vault, machine

        var title: LocalizedStringKey {
            switch self {
            case .routines: "Routines"
            case .skills: "Skills"
            case .apps: "Apps"
            case .vault: "Vault"
            case .machine: "Machine"
            }
        }
    }

    let contact: Contact
    let routines: RoutineList
    let skills: SkillList
    let apps: MCPServerList
    /// The apps it connects through the Nous Portal, shown on the Apps page.
    var connectors: ConnectorList? = nil
    let vault: VaultList
    let gateway: GatewayAddress
    let link: AppModel.Link
    let gatewayDetails: GatewayDetails?
    let loadGatewayDetails: () async -> Void
    let close: () -> Void

    @State private var tab = Tab.routines
    @State private var botEdit: BotEdit?
    @State private var isDropTarget = false
    @Environment(\.botEditing) private var botEditing

    /// The Mac panel's usual width, which the window's minimum width makes room for.
    static let width: CGFloat = 320

    #if os(iOS)
        private static let nameSize: CGFloat = 24
    #else
        private static let nameSize: CGFloat = 20
    #endif

    var body: some View {
        #if os(macOS)
            ScrollView {
                VStack(spacing: 18) {
                    header
                    // Centred when the tabs fit; scrolling sideways when they don't.
                    ViewThatFits(in: .horizontal) {
                        tabs
                        ScrollView(.horizontal, showsIndicators: false) { tabs }
                    }
                    page(tab)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.window)
            .botEditor($botEdit)
        #else
            // Grok's phone profile: a page pushed from the chat, who it is, then one card of rows,
            // each pushing its page.
            ScrollView {
                VStack(spacing: 24) {
                    header
                    PhoneProfileRows(
                        contact: contact, routines: routines, skills: skills, apps: apps, vault: vault
                    ) { tab in
                        ScrollView {
                            page(tab).padding(20)
                        }
                        .background(Theme.groupedPage)
                        .navigationTitle(tab.title)
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(Theme.groupedPage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let botEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            BotMenuItems(contact: contact, editing: botEditing, edit: $botEdit)
                        } label: {
                            Label("Edit Bot", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .botEditor($botEdit)
            .task(id: contact.id) {
                // The rows' counts; each page reloads its own when opened.
                async let routinesLoad: Void = routines.refresh()
                async let skillsLoad: Void = skills.refresh()
                async let appsLoad: Void = apps.refresh()
                _ = await (routinesLoad, skillsLoad, appsLoad)
                if isOnline { await vault.refresh() }
            }
        #endif
    }

    @ViewBuilder private func page(_ tab: Tab) -> some View {
        switch tab {
        case .routines:
            RoutinesView(list: routines, agentName: contact.name)
        case .skills:
            SkillsView(list: skills, agentName: contact.name)
        case .apps:
            AppsView(list: apps, connectors: connectors, agentName: contact.name)
                .id(apps.profile)
        case .vault:
            // Per Bot, so nothing typed for one agent can carry over to the next.
            VaultView(list: vault, agentName: contact.name, isOnline: isOnline)
                .id(vault.profile)
        case .machine:
            MachineView(
                details: contact.details, gateway: gateway, link: link, gatewayDetails: gatewayDetails,
                load: loadGatewayDetails)
        }
    }

    private var isOnline: Bool {
        if case .online = link { return true }
        return false
    }

    private var header: some View {
        VStack(spacing: 6) {
            AgentAvatar(contact: contactWithoutActivity, size: 88)
                .overlay {
                    if isDropTarget {
                        Circle().strokeBorder(Theme.ink.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }
                .botPictureDrop(isTargeted: $isDropTarget, enabled: botEditing?.unavailable == nil) { data in
                    botEdit = .usePicture(contact, data)
                }
            Text(contact.name)
                .font(.system(size: Self.nameSize, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            if let description = contact.details?.description {
                Text(description)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #if os(macOS)
                if let botEditing {
                    Menu {
                        BotMenuItems(contact: contact, editing: botEditing, edit: $botEdit)
                    } label: {
                        Label("Edit Bot", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.secondaryInk)
                            .frame(width: 28, height: 28)
                            .background(Theme.selection, in: Circle())
                            .contentShape(Circle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Edit Bot")
                    .padding(.top, 4)
                }
            #endif
        }
        .frame(maxWidth: .infinity)
    }

    private var tabs: some View {
        // Tight enough for all five in the Mac's side panel.
        HStack(spacing: 0) {
            tabButton("Routines", .routines)
            tabButton("Skills", .skills)
            tabButton("Apps", .apps)
            tabButton("Vault", .vault)
            tabButton("Machine", .machine)
        }
    }

    private func tabButton(_ title: LocalizedStringKey, _ value: Tab) -> some View {
        Button {
            tab = value
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tab == value ? Theme.ink : Theme.secondaryInk)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(tab == value ? Theme.selection : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.clickable)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    /// The panel's big avatar never pulses.
    private var contactWithoutActivity: Contact {
        var copy = contact
        copy.activity = .idle
        return copy
    }
}

// MARK: - Machine

private struct MachineView: View {
    let details: AgentDetails?
    let gateway: GatewayAddress
    let link: AppModel.Link
    let gatewayDetails: GatewayDetails?
    let load: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Agent") {
                row("Profile", details?.profile)
                row("Model", details?.model)
                row("Provider", details?.provider)
                row("Skills", details?.skillCount.map { String($0) })
            }
            section("Gateway") {
                row("Address", gateway.displayName)
                row("Version", gatewayDetails?.version)
                row("Status", statusText)
                row("Signed in as", gatewayDetails?.account)
            }
            #if os(macOS)
                if let settings = Self.hermesSettings {
                    Button("Open Hermes for advanced settings") { NSWorkspace.shared.open(settings) }
                        .buttonStyle(CardButtonStyle(primary: false))
                }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func section(_ title: LocalizedStringKey, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                rows()
            }
        }
    }

    @ViewBuilder private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(Theme.secondaryInk)
                Text(value).foregroundStyle(Theme.ink).textSelection(.enabled)
            }
            .font(.system(size: 13.5))
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
