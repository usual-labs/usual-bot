import HermesKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// The agent's card beside the chat: who it is, its routines, skills, apps and vault, and the machine it runs on.
/// A trailing column with tabs on the Mac; on iPhone a page of rows that open each page, as in
/// Settings.
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
            // One form per tab, with the Bot and the tabs scrolling at its top.
            page(tab, top: AnyView(macTop))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .botEditor($botEdit)
        #else
            // Pushed from the chat: who it is, then a row for each page, as in Settings.
            List {
                Section {
                } header: {
                    header.textCase(nil).padding(.bottom, 8)
                }
                PhoneProfileRows(
                    contact: contact, routines: routines, skills: skills, apps: apps, vault: vault
                ) { tab in
                    page(tab)
                        .navigationTitle(tab.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .listStyle(.insetGrouped)
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

    @ViewBuilder private func page(_ tab: Tab, top: AnyView? = nil) -> some View {
        switch tab {
        case .routines:
            RoutinesView(list: routines, agentName: contact.name, top: top)
        case .skills:
            SkillsView(list: skills, agentName: contact.name, top: top)
        case .apps:
            AppsView(list: apps, connectors: connectors, agentName: contact.name, top: top)
                .id(apps.profile)
        case .vault:
            // Per Bot, so nothing typed for one agent can carry over to the next.
            VaultView(list: vault, agentName: contact.name, isOnline: isOnline, top: top)
                .id(vault.profile)
        case .machine:
            MachineView(
                details: contact.details, gateway: gateway, link: link, gatewayDetails: gatewayDetails,
                load: loadGatewayDetails, top: top)
        }
    }

    private var isOnline: Bool {
        if case .online = link { return true }
        return false
    }

    #if os(macOS)
        /// The Bot and the tabs, as the first section of each page's form.
        private var macTop: some View {
            Section {
            } header: {
                VStack(spacing: 16) {
                    header
                    Picker("Page", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .clickable()
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .padding(.top, 8)
            }
        }
    #endif

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
                .scaledFont(size: Self.nameSize, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            if let description = contact.details?.description {
                Text(description)
                    .scaledFont(size: 13.5)
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
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .labelStyle(.iconOnly)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .clickable()
                    .help("Edit Bot")
                    .padding(.top, 4)
                }
            #endif
        }
        .frame(maxWidth: .infinity)
    }

    /// The panel's big avatar never pulses.
    private var contactWithoutActivity: Contact {
        var copy = contact
        copy.activity = .idle
        return copy
    }
}

/// A profile page: a grouped form whose switches keep the app's legible grey, under what the Mac
/// panel puts at the top of every page (the Bot and its tabs).
struct ProfileForm<Content: View>: View {
    let top: AnyView?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form {
            if let top { top }
            content()
        }
        .formStyle(.grouped)
        .toggleStyle(.systemSwitch)
    }
}

/// A page section's title, with its main action at the trailing end (New Routine, New App).
struct ProfileSectionHeader<Action: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let action: () -> Action

    init(_ title: LocalizedStringKey, @ViewBuilder action: @escaping () -> Action) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            // As `.inkProminent`, which a menu (New Item) doesn't take.
            action()
                .buttonStyle(.borderedProminent)
                .menuStyle(.button)
                .tint(Theme.primary)
                .foregroundStyle(Theme.primaryInk)
                .controlSize(.small)
                .textCase(nil)
                .clickable()
                .fixedSize()
        }
    }
}

/// A page's list while it loads.
struct ProfileLoading: View {
    var body: some View {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
    }
}

/// Why a page's list didn't load, and Try Again.
struct ProfileFailure: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { Task { await retry() } }.buttonStyle(.clickable(.bordered))
        }
    }
}

// MARK: - Machine

private struct MachineView: View {
    let details: AgentDetails?
    let gateway: GatewayAddress
    let link: AppModel.Link
    let gatewayDetails: GatewayDetails?
    let load: () async -> Void
    var top: AnyView?

    var body: some View {
        ProfileForm(top: top) {
            Section("Bot") {
                row("Profile", details?.profile)
                row("Model", details?.model)
                row("Provider", details?.provider)
                row("Skills", details?.skillCount.map { String($0) })
            }
            Section("Gateway") {
                row("Address", gateway.displayName)
                row("Version", gatewayDetails?.version)
                row("Status", statusText)
                row("Signed in as", gatewayDetails?.account)
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
