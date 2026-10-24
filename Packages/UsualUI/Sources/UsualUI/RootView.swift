import HermesKit
import SwiftUI

/// The main window: the connect screen until signed in, then contacts and the selected thread.
public struct RootView: View {
    @Bindable var model: AppModel
    let presenter: any SignInPresenter

    public init(model: AppModel, presenter: any SignInPresenter) {
        self.model = model
        self.presenter = presenter
    }

    public var body: some View {
        switch model.session {
        case .signedOut where model.isRestoring:
            SplashView()
        case .signedOut, .signingIn:
            ConnectView(model: model, presenter: presenter)
        case .signedIn(let gateway):
            ContactsSplitView(
                contacts: model.sidebarContacts, emptyText: emptyText,
                thread: { $0.kind == .agent ? model.thread(for: $0) : nil },
                room: { model.room(for: $0) },
                open: { model.openThread(for: $0) },
                select: { model.visibleContactID = $0 },
                createRoom: { try await model.createRoom(named: $0, agents: $1) },
                profile: { contact, close in
                    guard contact.kind == .agent else { return nil }
                    return ProfilePanel(
                        contact: contact, routines: model.routines(for: contact), skills: model.skills(for: contact),
                        gateway: gateway, link: model.link,
                        gatewayDetails: model.gatewayDetails, loadGatewayDetails: { await model.loadGatewayDetails() },
                        close: close)
                }
            ) { compact in
                GatewayStatusButton(gateway: gateway, link: model.link, compact: compact, signOut: model.signOut)
            }
            .environment(\.media, model.media)
        }
    }

    private var emptyText: LocalizedStringKey {
        if case .online = model.link { return "No agents on this gateway yet." }
        return "Connecting…"
    }
}

/// Contacts on the left, the selected thread on the right. On iPhone the split view collapses
/// into a list that pushes the thread.
struct ContactsSplitView<Footer: View>: View {
    let contacts: [Contact]
    var emptyText: LocalizedStringKey = "No agents yet."
    var thread: (Contact) -> ChatThread? = { _ in nil }
    var room: (Contact) -> RoomThread? = { _ in nil }
    var open: (Contact) -> Void = { _ in }
    /// Told which contact is on screen, so its replies don't count as unread.
    var select: (Contact.ID?) -> Void = { _ in }
    /// Creates a room from a name and its agents and returns the room's ID; `nil` hides New Room.
    var createRoom: ((String, [Contact]) async throws -> Contact.ID)?
    /// The profile panel for a contact, given a way to close it; `nil` when it has none.
    var profile: (Contact, @escaping () -> Void) -> ProfilePanel? = { _, _ in nil }
    /// Below the list; told whether the sidebar is the narrow window's rail.
    @ViewBuilder let footer: (_ compact: Bool) -> Footer

    @State private var showsNewRoom = false
    /// Filters the list by name or last message.
    @State private var query = ""
    #if os(macOS)
        /// The list's width as you left it: from the rail's 78 pt up to 380 pt.
        @AppStorage("sidebarWidth") private var listWidth = Double(Self.fullWidth)
        /// The width while you drag the sidebar's edge, and where the drag began.
        @State private var dragWidth: Double?
        @State private var dragStart: Double?
        @State private var windowWidth: CGFloat = 0
        @State private var isSearching = false
        @FocusState private var searchFocused: Bool
        /// The open chat, reopened at the next launch.
        @AppStorage("selectedContact") private var selection: Contact.ID?
        @AppStorage("showsProfile") private var showsProfile = false
    #else
        @State private var selection: Contact.ID?
        @State private var showsProfile = false
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .tint(Theme.ink)
            .sheet(isPresented: $showsNewRoom) {
                if let createRoom {
                    NewRoomSheet(agents: agents, create: createRoom) { selection = $0 }
                }
            }
            .onChange(of: selection, initial: true) { _, selected in select(scenePhase == .active ? selected : nil) }
            // A chat in a window you aren't looking at isn't being read.
            .onChange(of: scenePhase) { _, phase in select(phase == .active ? selection : nil) }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
            // The Mac lays the sidebar out itself: macOS 26's split view keeps its sidebar at 140 pt
            // or more and won't let an app set its width, so it can't become the 78 pt rail.
            HStack(spacing: 0) {
                sidebar(compact: showsRail)
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .trailing) { resizeEdge }
                detail
            }
            .animation(.smooth(duration: 0.25), value: showsRail)
            // Search and New Room ride in the window's toolbar, beside the window buttons; the
            // toolbar also gives the title area its height. Anything drawn under it is hidden.
            .sidebarToolbar(
                leading: max(0, sidebarWidth - 197), search: searchButton, newRoom: newRoomButton,
                shown: !showsRail
            )
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .frame(minWidth: Self.railWidth + Self.chatMinWidth)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                windowWidth = $0
            }
        #else
            NavigationSplitView {
                sidebar(compact: false)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
                    .searchable(text: $query)
                    // No title: the bar holds only the gateway status and New Room.
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { footer(true) }
                        ToolbarItem(placement: .primaryAction) { newRoomButton }
                    }
            } detail: {
                detail
            }
        #endif
    }

    /// The list, or in the rail (`compact`) avatars only.
    private func sidebar(compact: Bool) -> some View {
        VStack(spacing: 0) {
            #if os(macOS)
                if isSearching, !compact { searchField }
            #endif
            if contacts.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContactList(contacts: contacts, query: query, compact: compact, selection: $selection)
            }
            #if os(macOS)
                if compact {
                    newRoomButton
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
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
            if dragWidth == nil, windowWidth > 0, windowWidth - wanted < Self.chatMinWidth { return Self.railWidth }
            return wanted
        }

        private var showsRail: Bool { sidebarWidth < Self.minListWidth }

        private var searchButton: some View {
            Button("Search", systemImage: "magnifyingglass", action: toggleSearch)
                .keyboardShortcut("f")
                .help("Search")
        }

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

        /// The rail: as wide as the window's three buttons with their margins.
        private static var railWidth: Double { 78 }
        /// Narrower than this, the list's names and previews don't fit.
        private static var minListWidth: Double { 220 }
        private static var fullWidth: Double { 300 }
        private static var maxWidth: Double { 380 }
        /// The chat keeps at least this much; a narrower window folds the list to the rail.
        private static var chatMinWidth: Double { 360 }
    #endif

    @ViewBuilder private var detail: some View {
        if let contact = contacts.first(where: { $0.id == selection }), let room = room(contact) {
            RoomPane(
                contact: contact, members: members(of: contact), room: room,
                agents: Dictionary(
                    contacts.filter { $0.kind == .agent }.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }))
        } else if let contact = contacts.first(where: { $0.id == selection }) {
            let panel = profile(contact) { showsProfile = false }
            ThreadPane(
                contact: contact, members: members(of: contact), thread: thread(contact),
                open: { open(contact) }, toggleProfile: panel.map { _ in { showsProfile.toggle() } }
            )
            .inspector(isPresented: Binding(get: { showsProfile && panel != nil }, set: { showsProfile = $0 })) {
                if let panel {
                    panel.inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                }
            }
            #if os(macOS)
                .profileCloseButton(shown: showsProfile && panel != nil) { showsProfile = false }
            #endif
        } else {
            ContentUnavailableView(
                "No chat selected", systemImage: "bubble.left.and.bubble.right",
                description: Text("Pick an agent or a room from the list."))
        }
    }

    private var agents: [Contact] {
        contacts.filter { $0.kind == .agent }.sorted(by: Contact.rosterOrder)
    }

    @ViewBuilder private var newRoomButton: some View {
        if createRoom != nil {
            Button {
                showsNewRoom = true
            } label: {
                Label("New Room", systemImage: "plus")
            }
            .disabled(agents.count < NewRoomSheet.seats.lowerBound)
            .help("New Room")
        }
    }

    #if os(macOS)
        private var searchField: some View {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityHidden(true)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand(perform: closeSearch)
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .floatingSurface(in: Capsule())
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .onAppear { searchFocused = true }
        }

        private func toggleSearch() {
            if isSearching {
                closeSearch()
            } else {
                isSearching = true
            }
        }

        private func closeSearch() {
            isSearching = false
            query = ""
        }
    #endif

    private func members(of contact: Contact) -> [Contact] {
        let byID = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ContactList.members(of: contact, in: byID)
    }
}

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

#if os(macOS)
    extension View {
        /// Search and New Room at the list's right edge, level with the window buttons: one toolbar
        /// item that starts with a clear stretch as wide as the list leaves. In the rail only the
        /// item stays, empty, keeping the title area's height.
        @ViewBuilder fileprivate func sidebarToolbar(
            leading: CGFloat, search: some View, newRoom: some View, shown: Bool
        ) -> some View {
            let row = HStack(spacing: 8) {
                Color.clear.frame(width: shown ? leading : 0, height: 1)
                if shown {
                    search.sidebarGlassButton()
                    newRoom.sidebarGlassButton()
                }
            }
            .labelStyle(.iconOnly)
            if #available(macOS 26, *) {
                // The buttons bring their own glass; the toolbar shouldn't wrap them in more.
                toolbar { ToolbarItem(placement: .navigation) { row }.sharedBackgroundVisibility(.hidden) }
            } else {
                toolbar { ToolbarItem(placement: .navigation) { row } }
            }
        }

        /// The open profile panel's close button, at the window's top right over the panel and level
        /// with the window buttons; macOS 26 draws it as a Liquid Glass circle.
        @ViewBuilder fileprivate func profileCloseButton(shown: Bool, close: @escaping () -> Void) -> some View {
            let button = Button("Close Profile", systemImage: "xmark", action: close).help("Close Profile")
            if #available(macOS 26, *) {
                toolbar {
                    if shown {
                        ToolbarSpacer(.flexible)
                        ToolbarItem { button }
                    }
                }
            } else {
                toolbar {
                    if shown { ToolbarItem { button } }
                }
            }
        }

        /// A round Liquid Glass button: glass from macOS 26, a solid circle before.
        fileprivate func sidebarGlassButton() -> some View {
            buttonStyle(GlassCircleButtonStyle())
        }
    }
#endif

#if os(macOS)
    /// The sidebar's Search and New Room: an icon on a glass circle that answers a press.
    private struct GlassCircleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            GlassCircle(configuration: configuration)
        }

        private struct GlassCircle: View {
            let configuration: Configuration
            @Environment(\.isEnabled) private var isEnabled

            var body: some View {
                configuration.label
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .glassCircle()
                    .contentShape(Circle())
                    .scaleEffect(configuration.isPressed ? 0.94 : 1)
                    .opacity(isEnabled ? 1 : 0.45)
            }
        }
    }

    extension View {
        @ViewBuilder fileprivate func glassCircle() -> some View {
            if #available(macOS 26, *) {
                glassEffect(.regular.interactive(), in: Circle())
            } else {
                floatingSurface(in: Circle())
            }
        }
    }
#endif
