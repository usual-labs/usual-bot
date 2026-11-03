import HermesKit
import SwiftUI

/// The main window: the connect screen until signed in, then contacts and the selected thread.
public struct RootView<ConnectOptions: View, GatewayMenu: View>: View {
    @Bindable var model: AppModel
    let presenter: any SignInPresenter
    /// Settings on the connect screen, between the address and Sign In.
    let connectOptions: () -> ConnectOptions
    /// More items for the gateway menu, after the gateway's status.
    let gatewayMenu: () -> GatewayMenu
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #else
        @State private var showsSettings = false
    #endif

    public init(
        model: AppModel, presenter: any SignInPresenter,
        @ViewBuilder connectOptions: @escaping () -> ConnectOptions,
        @ViewBuilder gatewayMenu: @escaping () -> GatewayMenu
    ) {
        self.model = model
        self.presenter = presenter
        self.connectOptions = connectOptions
        self.gatewayMenu = gatewayMenu
    }

    public var body: some View {
        Group { content }
            .appPreferences()
            #if os(iOS)
                .sheet(isPresented: $showsSettings) {
                    // The gateway menu's items, such as Tailscale, live on Settings' Connection page.
                    SettingsView(model: model, connectionControls: AnyView(gatewayMenu()))
                }
                .overlay(alignment: .topTrailing) {
                    if case .signedOut = model.session, !model.isRestoring {
                        settingsButton.padding(16)
                    }
                }
            #endif
    }

    @ViewBuilder private var content: some View {
        switch model.session {
        case .signedOut where model.isRestoring:
            SplashView()
        case .signedOut, .signingIn:
            ConnectView(model: model, presenter: presenter, options: connectOptions)
        case .signedIn(let gateway):
            ContactsSplitView(
                contacts: model.sidebarContacts, sections: model.sections, emptyText: model.link.emptyListText,
                tryAgain: model.link.offersTryAgain ? { model.reconnect() } : nil,
                thread: { $0.kind == .agent ? model.thread(for: $0) : nil },
                room: { model.room(for: $0) },
                skills: { $0.kind == .agent ? model.skills(for: $0) : nil },
                open: { model.openThread(for: $0) },
                select: { model.visibleContactID = $0 },
                focused: { model.setWindowFocused($0) },
                settings: showSettings,
                requested: model.requestedContactID,
                openedRequested: { model.requestedContactID = nil },
                createRoom: { try await model.createRoom(named: $0, agents: $1) },
                renameRoom: { try await model.renameRoom($0, to: $1) },
                deleteRoom: { try await model.deleteRoom($0) },
                botEditing: BotEditing(model),
                currentID: { model.currentID(for: $0) },
                search: MessageSearching(
                    hits: { model.searchMessages($0) }, status: { model.messageSearchStatus($0) },
                    lookUp: { model.lookUpMessages($0) }, locate: { await model.locate($0) }),
                profile: { contact, close in
                    guard contact.kind == .agent else { return nil }
                    return ProfilePanel(
                        contact: contact, routines: model.routines(for: contact), skills: model.skills(for: contact),
                        apps: model.apps(for: contact), connectors: model.connectors(for: contact),
                        vault: model.vault(for: contact), gateway: gateway,
                        link: model.link,
                        gatewayDetails: model.gatewayDetails, loadGatewayDetails: { await model.loadGatewayDetails() },
                        close: close)
                }
            ) { compact in
                #if os(macOS)
                    let layout = compact ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        GatewayStatusButton(
                            gateway: gateway, link: model.link, compact: compact, signOut: model.signOut,
                            more: gatewayMenu)
                        settingsButton
                    }
                    .fixedSize(horizontal: compact, vertical: false)
                #else
                    // As in Grok's phone app, one round button; the gateway's state is its dot, and
                    // the rest of it is at the top of Settings.
                    phoneSettingsButton
                #endif
            }
            .environment(\.media, model.media)
            .environment(\.botPictures, model.pictures)
            .environment(\.voiceLive, model.voiceLive)
            .environment(\.screens, model)
            .environment(\.gatewayOnline, model.isOnline)
        }
    }

    private func showSettings() {
        #if os(macOS)
            openSettings()
        #else
            showsSettings = true
        #endif
    }

    private var settingsButton: some View {
        Button(action: showSettings) {
            Image(systemName: "gearshape")
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.clickable)
        .foregroundStyle(Theme.secondaryInk)
        .accessibilityLabel(Text("Settings"))
        .help("Settings")
    }

    #if os(iOS)
        private var phoneSettingsButton: some View {
            Button(action: showSettings) {
                // Sized like the + beside it, so the bar draws both as the same circle.
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(model.link.dotColor)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Theme.pane, lineWidth: 1.5))
                            .offset(x: 4, y: 4)
                    }
            }
            .buttonStyle(.clickable)
            .accessibilityLabel(Text("Settings"))
            .accessibilityValue(Text(model.link.statusText))
        }
    #endif
}

extension RootView where ConnectOptions == EmptyView, GatewayMenu == EmptyView {
    public init(model: AppModel, presenter: any SignInPresenter) {
        self.init(model: model, presenter: presenter, connectOptions: { EmptyView() }, gatewayMenu: { EmptyView() })
    }
}

/// Contacts on the left, the selected thread on the right. On iPhone the split view collapses
/// into a list that pushes the thread.
struct ContactsSplitView<Footer: View>: View {
    let contacts: [Contact]
    /// How the sidebar is grouped; `nil` lists everything together.
    var sections: SidebarSections?
    var emptyText = String(localized: "No agents yet.")
    /// Shown under `emptyText` as Try Again, when there's something to try again.
    var tryAgain: (() -> Void)?
    var thread: (Contact) -> ChatThread? = { _ in nil }
    var room: (Contact) -> RoomThread? = { _ in nil }
    /// An agent's skills, for a room's `/` menu.
    var skills: (Contact) -> SkillList? = { _ in nil }
    var open: (Contact) -> Void = { _ in }
    /// Told which contact is on screen, so its replies don't count as unread.
    var select: (Contact.ID?) -> Void = { _ in }
    /// Told whether you're at this window. A chat in one you aren't at isn't being read.
    var focused: (Bool) -> Void = { _ in }
    var settings: () -> Void = {}
    /// A chat to open from outside the list, such as a tapped notification.
    var requested: Contact.ID?
    var openedRequested: () -> Void = {}
    /// Creates a room from a name and its agents and returns the room's ID; `nil` hides New Room.
    var createRoom: ((String, [Contact]) async throws -> Contact.ID)?
    /// `nil` hides renaming and deleting rooms.
    var renameRoom: ((Contact, String) async throws -> Void)?
    var deleteRoom: ((Contact) async throws -> Void)?
    /// Making and changing Bots; `nil` hides New Bot and the Bot actions.
    var botEditing: BotEditing?
    /// A contact ID as it is now, after a Bot was renamed on the gateway.
    var currentID: (Contact.ID) -> Contact.ID = { $0 }
    /// Messages in every chat and room that match a search.
    var search = MessageSearching()
    /// The profile panel for a contact, given a way to close it; `nil` when it has none.
    var profile: (Contact, @escaping () -> Void) -> ProfilePanel? = { _, _ in nil }
    /// Below the list; told whether the sidebar is the narrow window's rail.
    @ViewBuilder let footer: (_ compact: Bool) -> Footer

    @State private var showsNewRoom = false
    @State private var showsNewBot = false
    /// Filters the list by name or last message.
    @State private var query = ""
    #if os(macOS)
        /// The list's width as you left it: from the rail's 78 pt up to 380 pt.
        @AppStorage("sidebarWidth") private var listWidth = Double(Self.fullWidth)
        /// The width while you drag the sidebar's edge, and where the drag began.
        @State private var dragWidth: Double?
        @State private var dragStart: Double?
        @State private var windowWidth: CGFloat = 0
        /// The open profile or room panel's usual width; 0 with none.
        @State private var panelWidth: CGFloat = 0
        @State private var showsPalette = false
        /// The open chat, reopened at the next launch.
        @AppStorage("selectedContact") private var selection: Contact.ID?
        @AppStorage("showsProfile") private var showsProfile = false
    #else
        @State private var selection: Contact.ID?
        @State private var showsProfile = false
    #endif
    @State private var isLooking = false
    /// A message chosen from search, until its chat has scrolled to it.
    @State private var jump: MessageJump?
    /// Loading a chat to find a message the gateway found, or why it couldn't be shown.
    @State private var finding: FindingNotice.State?
    @State private var findingTask: Task<Void, Never>?
    @State private var findingContact: Contact.ID?

    var body: some View {
        content
            .tint(Theme.ink)
            .environment(\.roomEditing, roomEditing)
            .environment(
                \.botEditing,
                // Deleting the open Bot closes its chat.
                botEditing?.afterDeleting { if selection == $0.id { selection = nil } }
            )
            .sheet(isPresented: $showsNewRoom) {
                if let createRoom {
                    NewRoomSheet(agents: agents, create: createRoom) { selection = $0 }
                }
            }
            .sheet(isPresented: $showsNewBot) {
                if let botEditing {
                    NewBotSheet(editing: botEditing) { selection = $0 }
                }
            }
            // A Bot renamed on the gateway keeps its chat open under its new ID.
            .onChange(of: contacts.map(\.id)) {
                if let selection, currentID(selection) != selection { self.selection = currentID(selection) }
            }
            .tracksLooking($isLooking)
            .onChange(of: selection, initial: true) { _, selected in
                #if os(iOS)
                    // A profile pushed over the last chat mustn't open over the next.
                    showsProfile = false
                #endif
                select(isLooking ? selected : nil)
                if jump?.contactID != selected { jump = nil }
                if findingTask != nil || finding != nil, findingContact != selected { stopFinding() }
                // Leaving a chat stops what played in it.
                MediaPlayback.shared.stop(in: "window")
            }
            .onChange(of: query) { search.lookUp(query) }
            .onChange(of: isLooking) { _, looking in
                select(looking ? selection : nil)
                focused(looking)
            }
            .onChange(of: requested, initial: true) { _, requested in
                guard let requested else { return }
                selection = currentID(requested)
                openedRequested()
            }
            // A closed window shows nothing, and it may not get a last scene phase.
            .onDisappear {
                select(nil)
                focused(false)
                MediaPlayback.shared.stop(in: "window")
            }
    }

    private var roomEditing: RoomEditing? {
        guard let renameRoom, let deleteRoom else { return nil }
        return RoomEditing(rename: renameRoom) { contact in
            try await deleteRoom(contact)
            if selection == contact.id { selection = nil }
        }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
            // The Mac lays the sidebar out itself: macOS 26's split view keeps its sidebar at 140 pt
            // or more and won't let an app set its width, so it can't become the 78 pt rail.
            HStack(spacing: 0) {
                sidebar(compact: showsRail)
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .trailing) { resizeEdge }
                detailPane
            }
            .animation(.smooth(duration: 0.25), value: showsRail)
            // Search and New Room ride in the window's toolbar, beside the window buttons; the
            // toolbar also gives the title area its height. Anything drawn under it is hidden.
            .sidebarToolbar(
                leading: max(0, sidebarWidth - (showsToggleInToolbar ? 229 : 197)), search: searchButton,
                newRoom: newButton, toggle: showsToggleInToolbar ? sidebarToggle : nil, shown: !showsRail
            )
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            // Room for the open panel too: without it, a narrow window's panel pushes the sidebar
            // and the chat off its sides.
            .frame(minWidth: Self.railWidth + Self.chatMinWidth + panelWidth)
            .onPreferenceChange(OpenPanelWidth.self) { panelWidth = $0 }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                windowWidth = $0
            }
            .focusedSceneValue(\.windowCommands, windowCommands)
            .overlay {
                if showsPalette {
                    CommandPalette(
                        contacts: contacts, members: members(of:),
                        canCreateRoom: createRoom != nil,
                        search: search, open: { selection = $0 }, openMessage: show,
                        newRoom: { showsNewRoom = true }, newBot: botEditing.map { _ in { showsNewBot = true } },
                        settings: settings, close: { showsPalette = false })
                }
            }
        #else
            NavigationSplitView {
                sidebar(compact: false)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
                    .searchable(text: $query)
                    // No title: the bar holds only the gateway status and New Room.
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { footer(false) }
                        ToolbarItem(placement: .primaryAction) { newButton }
                    }
            } detail: {
                // A stack of its own, so a chat can push its agent's profile.
                NavigationStack { detailPane }
            }
        #endif
    }

    /// The list, or in the rail (`compact`) avatars only.
    private func sidebar(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if contacts.isEmpty {
                VStack(spacing: 10) {
                    Text(verbatim: emptyText).multilineTextAlignment(.center)
                    if let tryAgain {
                        Button("Try Again", action: tryAgain)
                            .buttonStyle(.clickable)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .frame(minHeight: 44)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContactList(
                    contacts: contacts, sections: sections, query: query, compact: compact, selection: $selection,
                    messages: search.hits(query), status: search.status(query), openMessage: show)
            }
            #if os(macOS)
                if compact {
                    if canLeaveRail {
                        sidebarToggle
                            .frame(width: 44, height: 44)
                    }
                    searchButton
                        .labelStyle(.iconOnly)
                        .buttonStyle(.clickable)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    newButton
                        .labelStyle(.iconOnly)
                        // Not `.clickable`: a menu ignores that style and draws a grey box.
                        .buttonStyle(.plain)
                        .clickable()
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                footer(compact)
                    .padding(.horizontal, compact ? 0 : 14)
                    .padding(.vertical, 10)
            #endif
        }
        #if os(macOS)
            .background(Theme.window)
        #else
            // On iPhone the list is a screen of its own, in the chat's colour.
            .background(Theme.pane)
        #endif
    }

    #if os(macOS)
        /// The list narrows to the rail when you drag its edge in, or when the window leaves the
        /// chat too little room.
        private var sidebarWidth: CGFloat {
            let wanted = CGFloat(dragWidth ?? listWidth)
            if dragWidth == nil, windowWidth > 0, windowWidth - wanted - panelWidth < Self.chatMinWidth {
                return Self.railWidth
            }
            return wanted
        }

        private var showsRail: Bool { sidebarWidth < Self.minListWidth }

        private var searchButton: some View {
            Button("Search", systemImage: "magnifyingglass") { showsPalette = true }
                .help("Search (⌘K)")
        }

        /// The menu bar's commands for this window (`UsualBotCommands`).
        private var windowCommands: WindowCommands {
            // One sheet at a time.
            let free = !showsNewBot && !showsNewRoom
            let canMakeRoom = createRoom != nil && agents.count >= NewRoomSheet.seats.lowerBound
            let grouped = sections?.sections.isEmpty == false
            let blocks =
                grouped
                ? sections?.blocks(for: contacts) ?? []
                : [SidebarBlock(section: nil, contacts: contacts.sorted(by: Contact.rosterOrder))]
            let folds = !showsRail && grouped
            let ids = ChatOrder.shown(blocks) { folds && sections?.isFolded($0) == true }.map(\.id)
            var commands = WindowCommands(search: { showsPalette.toggle() })
            if botEditing != nil, free {
                commands.newBot = {
                    showsPalette = false
                    showsNewBot = true
                }
            }
            if canMakeRoom, free {
                commands.newRoom = {
                    showsPalette = false
                    showsNewRoom = true
                }
            }
            if !showsRail || canLeaveRail {
                commands.sidebar = (showsRail ? "Expand Sidebar" : "Collapse Sidebar", toggleSidebar)
            }
            if !ids.isEmpty {
                commands.previousChat = { selection = ChatOrder.step(from: selection, by: -1, in: ids) }
                commands.nextChat = { selection = ChatOrder.step(from: selection, by: 1, in: ids) }
            }
            return commands
        }

        private func toggleSidebar() {
            withAnimation(.smooth(duration: 0.25)) { listWidth = showsRail ? Self.fullWidth : Self.railWidth }
        }

        private var sidebarToggle: some View {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.clickable)
            .help(showsRail ? "Expand Sidebar (⌃⌘S)" : "Collapse Sidebar (⌃⌘S)")
            .accessibilityLabel(showsRail ? Text("Expand Sidebar") : Text("Collapse Sidebar"))
        }

        /// A window too narrow for the list keeps the rail, so a button there would do nothing.
        private var canLeaveRail: Bool { windowWidth - Self.fullWidth - panelWidth >= Self.chatMinWidth }

        /// The toolbar's row doesn't fit it in the narrowest list.
        private var showsToggleInToolbar: Bool { sidebarWidth >= 229 }

        /// The sidebar's edge: drag it to resize. Let go narrower than a list fits and it settles
        /// on the rail; pull the rail out far enough and it opens to the full list.
        private var resizeEdge: some View {
            Rectangle()
                .fill(Color.primary.opacity(0.001))
                .frame(width: 8)
                .offset(x: 4)
                .pointerStyle(.frameResize(position: .trailing))
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = dragStart ?? Double(sidebarWidth)
                            dragStart = start
                            dragWidth = min(max(start + drag.translation.width, Self.railWidth), Self.maxWidth)
                        }
                        .onEnded { _ in
                            let released = dragWidth ?? listWidth
                            let target: Double
                            if released < Self.minListWidth {
                                // Out of the rail opens the list; in from the list closes to the rail.
                                let fromRail = (dragStart ?? released) < Self.minListWidth
                                target = fromRail && released > Self.railWidth + 30 ? Self.fullWidth : Self.railWidth
                            } else {
                                target = released
                            }
                            withAnimation(.smooth(duration: 0.25)) {
                                listWidth = target
                                dragWidth = nil
                            }
                            dragStart = nil
                        }
                )
                .accessibilityHidden(true)
        }

        /// The rail: the window's three buttons with their margins, and room around its avatars.
        private static var railWidth: Double { 88 }
        /// Narrower than this, the list's names and previews don't fit.
        private static var minListWidth: Double { 220 }
        private static var fullWidth: Double { 280 }
        private static var maxWidth: Double { 380 }
        /// The chat keeps at least this much; a narrower window folds the list to the rail.
        private static var chatMinWidth: Double { 360 }
    #endif

    /// The chat, with word of a message search is loading it for.
    private var detailPane: some View {
        detail.findingNotice(finding, dismiss: stopFinding)
    }

    @ViewBuilder private var detail: some View {
        if let contact = contacts.first(where: { $0.id == selection }), let room = room(contact) {
            RoomPane(
                contact: contact, members: members(of: contact), room: room,
                agents: Dictionary(
                    contacts.filter { $0.kind == .agent }.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }),
                skills: skills, jump: jump(in: contact), jumped: { jump = nil })
        } else if let contact = contacts.first(where: { $0.id == selection }) {
            let panel = profile(contact) { showsProfile = false }
            ThreadPane(
                contact: contact, members: members(of: contact), thread: thread(contact),
                open: { open(contact) }, toggleProfile: panel.map { _ in { showsProfile.toggle() } },
                jump: jump(in: contact), jumped: { jump = nil }
            )
            #if os(macOS)
                .inspector(isPresented: Binding(get: { showsProfile && panel != nil }, set: { showsProfile = $0 })) {
                    if let panel {
                        panel.inspectorColumnWidth(min: 280, ideal: ProfilePanel.width, max: 420)
                    }
                }
                .preference(key: OpenPanelWidth.self, value: showsProfile && panel != nil ? ProfilePanel.width : 0)
                .profileCloseButton(shown: showsProfile && panel != nil) { showsProfile = false }
                .focusedSceneValue(
                    \.chatPanel,
                    panel.map { _ in
                        ChatPanelCommand(title: showsProfile ? "Hide Profile" : "Show Profile") {
                            showsProfile.toggle()
                        }
                    })
            #else
                // Pushed from the chat, as in Grok's phone app. Not an inspector: its content sits
                // in the chat's navigation stack, so its toolbar joins the chat's bar.
                .navigationDestination(
                    isPresented: Binding(get: { showsProfile && panel != nil }, set: { showsProfile = $0 })
                ) {
                    panel
                }
            #endif
        } else {
            ContentUnavailableView(
                "No chat selected", systemImage: "bubble.left.and.bubble.right",
                description: Text("Pick an agent or a room from the list.")
            )
            .paneChrome()
        }
    }

    private func show(_ hit: MessageHit) {
        stopFinding()
        if let itemID = hit.itemID {
            jump = MessageJump(contactID: hit.contactID, itemID: itemID)
            selection = hit.contactID
            return
        }
        // Found by the gateway in history this device hasn't loaded: open the chat, load it, then jump.
        selection = hit.contactID
        findingContact = hit.contactID
        finding = .finding
        findingTask = Task {
            let location = await search.locate(hit)
            guard !Task.isCancelled else { return }
            findingTask = nil
            switch location {
            case .item(let itemID):
                finding = nil
                jump = MessageJump(contactID: hit.contactID, itemID: itemID)
            case .unavailable(let reason):
                finding = .unavailable(reason)
                AccessibilityNotification.Announcement(reason).post()
                // Long enough to read; Dismiss or another chat clears it sooner.
                try? await Task.sleep(for: .seconds(8))
                if finding == .unavailable(reason) { finding = nil }
            }
        }
    }

    private func stopFinding() {
        findingTask?.cancel()
        findingTask = nil
        finding = nil
        findingContact = nil
    }

    private func jump(in contact: Contact) -> MessageJump? {
        jump?.contactID == contact.id ? jump : nil
    }

    private var agents: [Contact] {
        contacts.filter { $0.kind == .agent }.sorted(by: Contact.rosterOrder)
    }

    /// The +: New Bot and New Room, or just New Room where Bots can't be made.
    @ViewBuilder private var newButton: some View {
        if botEditing != nil {
            Menu {
                Button("New Bot…", systemImage: "person.crop.circle.badge.plus") { showsNewBot = true }
                if createRoom != nil {
                    Button("New Room…", systemImage: "person.2") { showsNewRoom = true }
                }
            } label: {
                Label("New", systemImage: "plus")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .help("New Bot or Room")
        } else if createRoom != nil {
            Button {
                showsNewRoom = true
            } label: {
                Label("New Room", systemImage: "plus")
            }
            .help("New Room")
        }
    }

    private func members(of contact: Contact) -> [Contact] {
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ContactList.members(of: contact, in: byID)
    }
}

#if os(macOS)
    extension View {
        /// Search and New Room at the list's right edge, level with the window buttons: one toolbar
        /// item that starts with a clear stretch as wide as the list leaves. In the rail only the
        /// item stays, empty, keeping the title area's height.
        @ViewBuilder fileprivate func sidebarToolbar(
            leading: CGFloat, search: some View, newRoom: some View, toggle: (some View)?, shown: Bool
        ) -> some View {
            let row = HStack(spacing: 8) {
                Color.clear.frame(width: shown ? leading : 0, height: 1)
                if shown {
                    if let toggle { toggle }
                    search.sidebarCircleButton()
                    newRoom.sidebarCircleButton()
                }
            }
            .labelStyle(.iconOnly)
            if #available(macOS 26, *) {
                // The buttons bring their own surface; the toolbar shouldn't wrap them in glass.
                toolbar { ToolbarItem(placement: .navigation) { row }.sharedBackgroundVisibility(.hidden) }
            } else {
                toolbar { ToolbarItem(placement: .navigation) { row } }
            }
        }

        /// The open profile panel's close button, at the window's top right over the panel and level
        /// with the window buttons; macOS 26 draws it as a glass circle.
        @ViewBuilder fileprivate func profileCloseButton(shown: Bool, close: @escaping () -> Void) -> some View {
            let button = Button("Close Profile", systemImage: "xmark", action: close)
                .help("Close Profile")
                .sidebarCircleButton()
            if #available(macOS 26, *) {
                toolbar {
                    if shown {
                        ToolbarSpacer(.flexible)
                        ToolbarItem { button }.sharedBackgroundVisibility(.hidden)
                    }
                }
            } else {
                toolbar {
                    if shown { ToolbarItem { button } }
                }
            }
        }

        /// A round button, on the surface the name pill beside it uses.
        fileprivate func sidebarCircleButton() -> some View {
            buttonStyle(CircleButtonStyle())
        }
    }
#endif

#if os(macOS)
    /// The sidebar's Search and New Room: an icon on a circle that answers a press.
    private struct CircleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            FloatingCircle(configuration: configuration)
        }

        private struct FloatingCircle: View {
            let configuration: Configuration
            @Environment(\.isEnabled) private var isEnabled

            var body: some View {
                configuration.label
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .floatingSurface(in: Circle())
                    .contentShape(Circle())
                    .scaleEffect(configuration.isPressed ? 0.94 : 1)
                    .opacity(isEnabled ? 1 : 0.45)
                    .clickable()
            }
        }
    }
#endif
