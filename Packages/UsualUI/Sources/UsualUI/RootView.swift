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
        /// The browser and computer setup, from the footer's puzzle-piece button.
        @State private var showsPlugins = false
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
            #if os(macOS)
                .sheet(isPresented: $showsPlugins) {
                    SheetForm(title: Text("Plugins"), action: SheetAction(title: "Done") { showsPlugins = false }) {
                        Form {
                            PluginsSettings(model: model) { bot, message in
                                // Typed into the chat's box, unsent, and the chat opened.
                                model.thread(for: bot).prefill = message
                                model.requestedContactID = bot.id
                                showsPlugins = false
                            }
                        }
                    }
                    .frame(width: 520, height: 600)
                }
            #endif
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
                contacts: model.sidebarContacts, sections: model.sections, hiddenBots: model.hiddenBots,
                emptyText: model.link.emptyListText,
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
                createRoom: { try await model.createRoom(named: $0, agents: $1, routing: $2, lead: $3) },
                newRoomRouting: { await model.newRoomRouting() },
                roomsUnavailable: model.roomEditingUnavailable,
                saveRoomSettings: { try await model.saveRoomSettings($0, $1) },
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
                        thread: model.thread(for: contact), close: close)
                },
                update: model.update
            ) { compact in
                #if os(macOS)
                    // The connection in a capsule, then Plugins and Settings in circles. The rail
                    // keeps only Settings (the developer's call); Search and New stay in the menu
                    // bar, with their shortcuts.
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            if !compact {
                                GatewayStatusButton(
                                    gateway: gateway, link: model.link, signOut: model.signOut, more: gatewayMenu
                                )
                                .padding(.horizontal, 14)
                                .frame(height: ThreadPane.barItemHeight)
                                .glassEffect(.regular.interactive(), in: Capsule())
                                pluginsButton.roundGlass()
                            }
                            settingsButton.roundGlass()
                        }
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
            .environment(\.drafts, model.drafts)
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

    #if os(macOS)
        private var pluginsButton: some View {
            Button("Plugins", systemImage: "puzzlepiece.extension") { showsPlugins = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.clickable(.borderless))
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 32, height: 32)
                .help("Plugins: set up a Bot’s browser and computer")
        }
    #endif

    private var settingsButton: some View {
        Button("Settings", systemImage: "gearshape", action: showSettings)
            .labelStyle(.iconOnly)
            #if os(macOS)
                .buttonStyle(.clickable(.borderless))
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 32, height: 32)
            #else
                // It floats over the connect screen.
                .buttonStyle(.clickable(.glass))
                .buttonBorderShape(.circle)
                .controlSize(.large)
            #endif
            .help("Settings")
    }

    #if os(iOS)
        /// A toolbar item, which the bar draws in glass; the gateway's state is its dot.
        private var phoneSettingsButton: some View {
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(model.link.dotColor)
                            .frame(width: 8, height: 8)
                            .offset(x: 3, y: 3)
                    }
            }
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
    /// Not listed, but still in their rooms.
    var hiddenBots: [Contact] = []
    var emptyText = String(localized: "No Bots yet.")
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
    var createRoom: ((String, [Contact], RoomRouting, Contact?) async throws -> Contact.ID)?
    /// The ways of choosing who answers that a new room can start with.
    var newRoomRouting: () async -> [RoomRouting] = { [] }
    /// Why rooms can't be changed right now, such as being offline.
    var roomsUnavailable: String?
    var saveRoomSettings: (Contact, RoomSettings) async throws -> Void = { _, _ in }
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
    /// Offers a newer TestFlight build below the list; not in the rail.
    var update: AppUpdate?
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
        /// ⌘ is held, so the sidebar shows which number opens each chat.
        @State private var commandHeld = false
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
                // Hiding or deleting the open Bot closes its chat.
                botEditing?.afterRemoving { if selection == $0.id { selection = nil } }
            )
            .sheet(isPresented: $showsNewRoom) {
                if let createRoom {
                    NewRoomSheet(agents: agents, create: createRoom, routings: newRoomRouting) { selection = $0 }
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
        return RoomEditing(
            unavailable: roomsUnavailable, rename: renameRoom,
            delete: { contact in
                try await deleteRoom(contact)
                if selection == contact.id { selection = nil }
            }, saveSettings: saveRoomSettings)
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
            // The Mac lays the sidebar out itself: macOS 26's split view keeps its sidebar at 140 pt
            // or more and won't let an app set its width, so it can't become the 78 pt rail.
            HStack(spacing: 0) {
                sidebar(compact: showsRail)
                    .environment(\.chatShortcuts, commandHeld ? ChatOrder.numbered(shownChats.map(\.id)) : [:])
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .trailing) { resizeEdge }
                detailPane
            }
            .animation(.smooth(duration: 0.25), value: showsRail)
            // Search and New ride in the window's toolbar, beside the window buttons; the toolbar
            // also gives the title area its height. Anything drawn under it is hidden.
            .sidebarToolbar(
                leading: max(0, sidebarWidth - (showsToggleInToolbar ? Self.toolbarGroupWidth : Self.toolbarPairWidth)),
                search: searchButton, newRoom: newButton, toggle: showsToggleInToolbar ? sidebarToggle : nil,
                shown: !showsRail
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
            .tracksCommandHeld($commandHeld)
            .environment(\.messageBoxTakesTyping, !showsPalette)
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
                    .navigationTitle("Chats")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { footer(false) }
                        ToolbarItem(placement: .topBarTrailing) { newButton }
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
                ContentUnavailableView {
                    EmptyView()
                } description: {
                    Text(verbatim: emptyText)
                } actions: {
                    if let tryAgain {
                        Button("Try Again", action: tryAgain).buttonStyle(.clickable(.bordered))
                    }
                }
            } else {
                ContactList(
                    contacts: contacts, sections: sections, hiddenBots: hiddenBots, query: query, compact: compact,
                    selection: $selection,
                    messages: search.hits(query), status: search.status(query), openMessage: show)
            }
        }
        #if os(macOS)
            // The list scrolls under the window buttons and the toolbar, on the chat header's glass,
            // and under the footer, which floats in glass like the chat's message box.
            .overlay(alignment: .top) { HeaderGlass(ground: Theme.window).frame(height: 0) }
            .safeAreaBar(edge: .bottom, spacing: 0) { sidebarFooter(compact: compact) }
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            .background(Theme.window)
        #else
            .safeAreaInset(edge: .bottom) {
                if let update { UpdateBanner(update: update).padding(.horizontal, 16).padding(.bottom, 8) }
            }
        #endif
    }

    #if os(macOS)
        /// The footer (the connection and Settings, each in its own glass); in the rail, Expand
        /// Sidebar above Settings, in a circle of its own.
        private func sidebarFooter(compact: Bool) -> some View {
            VStack(spacing: 8) {
                if compact, canLeaveRail {
                    sidebarToggle
                        .labelStyle(.iconOnly)
                        .buttonStyle(.clickable(.borderless))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 32, height: 32)
                        .roundGlass()
                }
                if !compact, let update { UpdateBanner(update: update) }
                footer(compact)
            }
            // The list's 10 pt side inset, so the glass lines up with the rows' highlight and the
            // top bar; level with the message box at the bottom.
            .padding(.horizontal, compact ? 0 : 10)
            .padding(.bottom, ThreadPane.barEdgeMargin)
        }
    #endif

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
            let shown = shownChats
            let ids = shown.map(\.id)
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
            let numbers = ChatOrder.numbered(ids)
            commands.numberedChats = shown.filter { numbers[$0.id] != nil }.map { chat in
                (chat.name, { selection = chat.id })
            }
            return commands
        }

        /// The sidebar's chats in order, without those in folded sections. The rail folds nothing.
        private var shownChats: [Contact] {
            let blocks = SidebarBlock.blocks(for: contacts, in: sections?.sections ?? [])
            let folds = !showsRail && sections?.sections.isEmpty == false
            return ChatOrder.shown(blocks) { folds && sections?.isFolded($0) == true }
        }

        private func toggleSidebar() {
            withAnimation(.smooth(duration: 0.25)) { listWidth = showsRail ? Self.fullWidth : Self.railWidth }
        }

        private var sidebarToggle: some View {
            Button(
                showsRail ? "Expand Sidebar" : "Collapse Sidebar", systemImage: "sidebar.left",
                action: toggleSidebar
            )
            .help(showsRail ? "Expand Sidebar (⌃⌘S)" : "Collapse Sidebar (⌃⌘S)")
        }

        /// A window too narrow for the list keeps the rail, so a button there would do nothing.
        private var canLeaveRail: Bool { windowWidth - Self.fullWidth - panelWidth >= Self.chatMinWidth }

        /// The toolbar's row doesn't fit it in the narrowest list.
        private var showsToggleInToolbar: Bool { sidebarWidth >= Self.toolbarGroupWidth }

        /// What the window buttons and the toolbar's glass group take from the list's width, with
        /// and without the sidebar toggle. Measured from screenshots.
        private static var toolbarGroupWidth: Double { 229 }
        private static var toolbarPairWidth: Double { 197 }

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
                    (contacts + hiddenBots).filter { $0.kind == .agent }.map { ($0.id, $0) },
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
                .sidePanel(
                    isPresented: showsProfile && panel != nil, widthKey: "profileWidth", idealWidth: ProfilePanel.width,
                    widthRange: ProfilePanel.width...480, closeTitle: "Close Profile"
                ) {
                    showsProfile = false
                } panel: {
                    panel
                }
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
                description: Text("Pick a Bot or a room from the list.")
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
        let byID = Dictionary((contacts + hiddenBots).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ContactList.members(of: contact, in: byID)
    }
}

#if os(macOS)
    extension View {
        /// Search and New at the list's right edge, level with the window buttons, in the toolbar's
        /// own glass. A clear item as wide as the list leaves pushes them there; it has no glass of
        /// its own. In the rail only that item stays, empty, keeping the title area's height.
        fileprivate func sidebarToolbar(
            leading: CGFloat, search: some View, newRoom: some View, toggle: (some View)?, shown: Bool
        ) -> some View {
            toolbar {
                ToolbarItem(placement: .navigation) {
                    Color.clear.frame(width: shown ? leading : 0, height: 1).accessibilityHidden(true)
                }
                .sharedBackgroundVisibility(.hidden)
                if shown {
                    ToolbarItemGroup(placement: .navigation) {
                        if let toggle { toggle }
                        search
                        newRoom
                    }
                }
            }
        }
    }
#endif

#if os(macOS)
    extension View {
        /// A round glass button as tall as the header's: the sidebar footer's Settings and the
        /// rail's Expand Sidebar.
        fileprivate func roundGlass() -> some View {
            frame(width: ThreadPane.barItemHeight, height: ThreadPane.barItemHeight)
                .glassEffect(.regular.interactive(), in: Circle())
        }
    }
#endif
