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
                        contact: contact, routines: model.routines(for: contact), gateway: gateway, link: model.link,
                        gatewayDetails: model.gatewayDetails, loadGatewayDetails: { await model.loadGatewayDetails() },
                        close: close)
                }
            ) {
                GatewayStatusButton(gateway: gateway, link: model.link, signOut: model.signOut)
            }
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
    @ViewBuilder let footer: Footer

    @State private var showsNewRoom = false
    /// Filters the list by name or last message.
    @State private var query = ""
    #if os(macOS)
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
        NavigationSplitView {
            VStack(spacing: 0) {
                #if os(macOS)
                    if isSearching { searchField }
                #endif
                if contacts.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContactList(contacts: contacts, query: query, selection: $selection)
                }
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(Theme.window)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
            #if os(macOS)
                .toolbar(removing: .sidebarToggle)
                .sidebarButtons(search: searchButton, newRoom: newRoomButton)
            #else
                .searchable(text: $query)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { newRoomButton }
                }
            #endif
        } detail: {
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
            } else {
                ContentUnavailableView(
                    "No chat selected", systemImage: "bubble.left.and.bubble.right",
                    description: Text("Pick an agent or a room from the list."))
            }
        }
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
        private var searchButton: some View {
            Button("Search", systemImage: "magnifyingglass", action: toggleSearch)
                .keyboardShortcut("f")
                .help("Search")
        }

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
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
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
    ContactsSplitView(contacts: SampleData.contacts()) { EmptyView() }
        .frame(width: 1000, height: 640)
}

#if os(macOS)
    extension View {
        /// Search and New Room beside the window buttons. From macOS 26 they sit at the sidebar's
        /// right edge as two Liquid Glass circles; before that, as a plain toolbar group.
        @ViewBuilder fileprivate func sidebarButtons(search: some View, newRoom: some View) -> some View {
            if #available(macOS 26, *) {
                toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem { search }
                    ToolbarSpacer(.fixed)
                    ToolbarItem { newRoom }
                }
            } else {
                toolbar {
                    ToolbarItemGroup {
                        search
                        newRoom
                    }
                }
            }
        }
    }
#endif
