import HermesKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// The agent's card beside the chat: who it is, this chat's model, thinking and context, a row for
/// each of its pages (routines, skills, apps, vault, the machine it runs on) and its next routines.
/// A trailing column on the Mac, where a row opens its page in place with a glass back button; on
/// iPhone a list whose rows push each page, as in Settings.
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
    /// The agent's chat, whose model, thinking and context the profile shows.
    var thread: ChatThread? = nil
    let close: () -> Void

    /// The Mac panel's open page; none shows the Bot's overview.
    @State private var page: Tab?
    @State private var botEdit: BotEdit?
    @State private var isDropTarget = false
    @State private var showsWholeDescription = false
    @State private var showsBarTitle = false
    @Environment(\.botEditing) private var botEditing

    /// The Mac panel's width until you drag it, and the narrowest it goes.
    static let width: CGFloat = 390

    var body: some View {
        #if os(macOS)
            Group {
                if let page {
                    self.page(page, top: AnyView(pageTitle(page)))
                } else {
                    ProfileForm(top: nil) { overview }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { backButton }
            .overlay(alignment: .topTrailing) { editMenu }
            .onExitCommand(perform: page == nil ? nil : { page = nil })
            .onChange(of: contact.id) { page = nil }
            .botEditor($botEdit)
            .task(id: contact.id) { await loadCounts() }
        #else
            // Pushed from the chat and laid out like a contact's info page: the Bot centred at the
            // top, then Settings rows. Its name moves into the bar once the top scrolls away.
            List { overview }
                .listStyle(.insetGrouped)
                .navigationTitle(contact.name)
                .navigationBarTitleDisplayMode(.inline)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > Self.nameScrollsAway
                } action: { _, isAway in
                    withAnimation(.easeOut(duration: 0.2)) { showsBarTitle = isAway }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(contact.name)
                            .font(.headline)
                            .lineLimit(1)
                            .opacity(showsBarTitle ? 1 : 0)
                            .accessibilityHidden(!showsBarTitle)
                    }
                    if let botEditing {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                BotMenuItems(
                                    contact: contact, editing: botEditing, edit: $botEdit, includesRemoval: false)
                            } label: {
                                Label("Edit Bot", systemImage: "ellipsis")
                            }
                        }
                    }
                }
                .botEditor($botEdit)
                .task(id: contact.id) { await loadCounts() }
        #endif
    }

    #if os(iOS)
        /// About where the centred name passes under the bar.
        private static let nameScrollsAway: CGFloat = 150

        /// Hide and Delete at the end, as a contact's page puts its destructive actions.
        @ViewBuilder private var removal: some View {
            if let botEditing {
                Section {
                    Button("Hide Bot") { botEdit = .hide(contact) }
                    if botEditing.canDelete(contact) {
                        Button("Delete Bot…", role: .destructive) { botEdit = .delete(contact) }
                    }
                } footer: {
                    if let reason = botEditing.unavailable {
                        Text(reason)
                    } else {
                        Text("A hidden Bot keeps working and comes back from Settings › General.")
                    }
                }
                .disabled(botEditing.unavailable != nil)
            }
        }
    #endif

    /// The Bot, this chat's settings, the rows for its pages and its next routines.
    @ViewBuilder private var overview: some View {
        Section {
        } header: {
            header
                .textCase(nil)
                #if os(macOS)
                    // As the pages' titles, under the panel's round buttons.
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                #else
                    .padding(.bottom, -8)
                #endif
        }
        #if os(iOS)
            if let description = contact.details?.description {
                Section { ProfileAbout(description: description) }
            }
            if let thread {
                PhoneChatSection(thread: thread, agentName: contact.name, agentDefault: contact.details)
            }
        #else
            if let thread {
                ChatModelSection(thread: thread, agentName: contact.name, agentDefault: contact.details)
            }
        #endif
        ProfileRows(
            contact: contact, routines: routines, skills: skills, apps: apps, vault: vault,
            open: { page = $0 }
        ) { tab in
            page(tab)
                #if os(iOS)
                    .navigationTitle(tab.title)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        NextRoutines(routines: routines) { page = .routines }
        #if os(iOS)
            removal
        #endif
    }

    /// The rows' counts; each page reloads its own when opened.
    private func loadCounts() async {
        async let routinesLoad: Void = routines.refresh()
        async let skillsLoad: Void = skills.refresh()
        async let appsLoad: Void = apps.refresh()
        _ = await (routinesLoad, skillsLoad, appsLoad)
        if isOnline { await vault.refresh() }
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
        /// Back to the overview from a page, level with the close button. Esc and ⌘[ do the same.
        @ViewBuilder private var backButton: some View {
            if page != nil {
                Button {
                    page = nil
                } label: {
                    SidePanelIcon(systemName: "chevron.left")
                }
                .buttonStyle(.clickable)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back to \(contact.name)")
                .accessibilityLabel(Text("Back to \(contact.name)"))
                .padding(.top, 9)
                .padding(.leading, 8)
                .ignoresSafeArea(.container, edges: .top)
            }
        }

        /// A page's title and whose it is, at the top of its form, under the panel's round buttons.
        private func pageTitle(_ tab: Tab) -> some View {
            Section {
            } header: {
                HStack(spacing: 10) {
                    AgentAvatar(contact: contactWithoutActivity, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tab.title)
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(contact.name)
                            .zoomedFont(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .textCase(nil)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }

        /// Rename, picture and delete, beside the panel's close button. A menu with a drawn label
        /// takes the plain style and its own pointing hand (see known issues).
        @ViewBuilder private var editMenu: some View {
            if let botEditing {
                Menu {
                    BotMenuItems(contact: contact, editing: botEditing, edit: $botEdit)
                } label: {
                    SidePanelIcon(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .clickable()
                .help("Edit Bot")
                .accessibilityLabel(Text("Edit Bot"))
                .sidePanelTopRow(beforeClose: true)
            }
        }
    #endif

    /// The Bot's picture, its name and what it's doing: centred on iPhone, with the description in
    /// its own card below; beside each other in the Mac panel, with the description under them.
    @ViewBuilder private var header: some View {
        #if os(iOS)
            VStack(spacing: 4) {
                avatar(size: 96)
                    .padding(.bottom, 8)
                Text(contact.name)
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                statusLine
            }
            .frame(maxWidth: .infinity)
        #else
            macHeader
        #endif
    }

    private func avatar(size: CGFloat) -> some View {
        AgentAvatar(contact: contactWithoutActivity, size: size)
            .overlay {
                if isDropTarget {
                    Circle().strokeBorder(
                        Theme.ink.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            .botPictureDrop(isTargeted: $isDropTarget, enabled: botEditing?.unavailable == nil) { data in
                botEdit = .usePicture(contact, data)
            }
    }

    private var statusLine: some View {
        HStack(spacing: 5) {
            Circle().fill(isOnline ? Theme.online : Theme.secondaryInk).frame(width: 7, height: 7)
            Text(status)
        }
        .zoomedFont(.subheadline)
        .foregroundStyle(Theme.secondaryInk)
        .accessibilityElement(children: .combine)
    }

    /// The Bot's picture beside its name and what it's doing, then its description, cut to three
    /// lines until More.
    private var macHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatar(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .scaledFont(size: 20, weight: .semibold)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    statusLine
                }
                Spacer(minLength: 0)
            }
            if let description = contact.details?.description {
                VStack(alignment: .leading, spacing: 2) {
                    Text(description)
                        .scaledFont(size: 13.5)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(showsWholeDescription ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if description.count > Self.longDescription {
                        Button(showsWholeDescription ? "Less" : "More") { showsWholeDescription.toggle() }
                            .buttonStyle(.clickable(.borderless))
                            .zoomedFont(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// About where three lines run out at the panel's narrowest.
    private static let longDescription = 140

    /// What the Bot is doing, or why it can't be reached.
    private var status: String {
        switch link {
        case .connecting: return String(localized: "Connecting…")
        case .offline: return String(localized: "Offline")
        case .online: return contact.activity == .idle ? String(localized: "Online") : contact.activity.label
        }
    }

    /// The panel's avatar never pulses.
    private var contactWithoutActivity: Contact {
        var copy = contact
        copy.activity = .idle
        return copy
    }
}

/// A profile page: a grouped form whose switches keep the app's legible grey, under what the Mac
/// panel puts at the top of every page (its title and whose it is).
struct ProfileForm<Content: View>: View {
    let top: AnyView?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form {
            if let top { top }
            content()
        }
        .formStyle(.grouped)
        .thinScroller()
        .toggleStyle(.systemSwitch)
    }
}

/// A section's title in the profile panel, every section's, with the page's main action at the
/// trailing end (New Routine, New App) as a bare icon: give it a `.help` naming it. Styled here:
/// the grouped form drew some plain titles small and grey and others large and bold.
struct ProfileSectionHeader<Action: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let action: () -> Action

    init(_ title: LocalizedStringKey, @ViewBuilder action: @escaping () -> Action) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title)
                .zoomedFont(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            // A ghost button, the developer's choice over a filled one. A system style, which a
            // menu (New Item) takes too.
            action()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .zoomedFont(size: 13, weight: .medium)
                .foregroundStyle(Theme.secondaryInk)
                .textCase(nil)
                .clickable()
                .fixedSize()
        }
    }
}

extension ProfileSectionHeader where Action == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
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
