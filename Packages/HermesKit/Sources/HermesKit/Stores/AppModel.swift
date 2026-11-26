import Foundation
import Observation
import os

/// The app's top-level state: which gateway it's signed in to, whether the socket is up,
/// and the contacts it reports.
@MainActor
@Observable
public final class AppModel {
    public enum Session: Equatable {
        case signedOut
        case signingIn(GatewayAddress)
        case signedIn(GatewayAddress)
    }

    public enum Link: Equatable {
        case connecting
        case online(GatewayReady.Dialect)
        /// Lost the gateway; retrying in the background.
        case offline(String)
    }

    public internal(set) var session: Session = .signedOut
    public internal(set) var link: Link = .connecting
    /// The agents and rooms the gateway reports, in its own terms. Show `sidebarContacts` instead.
    public internal(set) var contacts: [Contact] = []
    /// Bots hidden from the sidebar, here or in the official app. They still work, and still reply
    /// in rooms; Settings lists them to show again.
    public internal(set) var hiddenBots: [Contact] = []
    /// The chat on screen, if any. Its replies don't count as unread.
    public var visibleContactID: Contact.ID? {
        didSet {
            showVisibleChat()
            if let visibleContactID { alertsCleared?(visibleContactID) }
            if visibleContactID != oldValue { reportFocus() }
        }
    }
    /// A chat to open, say because you tapped its notification. The window clears it.
    public var requestedContactID: Contact.ID?
    /// Version, health and account, once the Machine tab asked for them.
    public internal(set) var gatewayDetails: GatewayDetails?
    /// The last sign-in or connection problem, for the connect screen.
    public internal(set) var problem: String?
    /// What the user last typed into the gateway field.
    public var gatewayInput: String
    /// Reading the saved sign-in at launch (the Keychain may ask first): a splash, not the connect
    /// screen, shows meanwhile.
    public private(set) var isRestoring: Bool
    /// Set by the app to hear what you aren't looking at, e.g. to notify you. Rooms are contacts too.
    @ObservationIgnored public var agentAlerted: ((Contact, AgentAlert) -> Void)?
    /// A request alerted about is over: answered elsewhere, or withdrawn. Gets the alert's ID.
    @ObservationIgnored public var alertWithdrawn: ((String) -> Void)?
    /// You've seen a chat, or signed out (`nil`), so what was said about it can go.
    @ObservationIgnored public var alertsCleared: ((Contact.ID?) -> Void)?

    /// The gateways this device is signed in to, the one in use among them.
    public internal(set) var gateways: [SavedGateway] = []
    /// Where Cancel goes back to while you add a gateway (`addGateway()`).
    public internal(set) var returnGatewayID: SavedGateway.ID?
    /// Gateways not in use that have notifications waiting (`showNews(on:)`).
    public internal(set) var gatewaysWithNews: Set<SavedGateway.ID> = []

    let tokenStore: any TokenStore
    let http: any HTTPTransport
    private let makeSocket: GatewayConnector.SocketFactory
    let defaults: UserDefaults
    /// Where the window keeps the open chat (`rememberedKeys`): the app's own defaults, which
    /// `@AppStorage` reads, even when the model's are the demo's.
    let selectionDefaults: UserDefaults
    @ObservationIgnored var gatewayList: GatewayList
    let cache: OfflineCache
    @ObservationIgnored var lastSaved: OfflineCache.Snapshot?
    var auth: AuthSession?
    var signInTask: Task<Void, Never>?
    var linkTask: Task<Void, Never>?
    /// Whether the app is on screen; the socket stays closed while it isn't.
    var isForeground = true
    /// iOS gave the app a moment in the background (`checkIn()`, `warmUp`).
    var isCheckingIn = false
    /// Counts roster reads, so `checkIn()` knows when this link has read the gateway.
    @ObservationIgnored var rosterReads = 0
    /// When the app came back, or a notification was tapped, until the chat on screen is ready: `Trace`'s `resume`.
    @ObservationIgnored var resumedAt: ContinuousClock.Instant?
    /// The socket while the link is online.
    @ObservationIgnored var channel: JSONRPCChannel?
    /// The gateway process's event numbering, for replaying what a short drop missed.
    @ObservationIgnored private var replayEpoch: String?
    @ObservationIgnored var threads: [Contact.ID: ChatThread] = [:]
    @ObservationIgnored var routineLists: [Contact.ID: RoutineList] = [:]
    @ObservationIgnored var skillLists: [Contact.ID: SkillList] = [:]
    @ObservationIgnored var vaultLists: [Contact.ID: VaultList] = [:]
    @ObservationIgnored var appLists: [Contact.ID: MCPServerList] = [:]
    @ObservationIgnored var connectorLists: [Contact.ID: ConnectorList] = [:]
    /// Bots made, renamed, re-pictured or deleted here that a roster read may not show yet.
    @ObservationIgnored var rosterHolds = RosterHolds()
    /// Where Bots renamed on the gateway (`hermes profile rename`) went, old ID to new, so whatever
    /// still holds an old ID can follow it (`currentID(for:)`).
    @ObservationIgnored var renamedAgents: [Contact.ID: Contact.ID] = [:]
    @ObservationIgnored var rooms: [Contact.ID: RoomThread] = [:]
    /// Agents' computers, once a chat asked about one.
    @ObservationIgnored var screens: [Contact.ID: BotScreen] = [:]
    /// Agents' browsers (`usual-bot` plugin), once a chat asked about one.
    @ObservationIgnored var browsers: [Contact.ID: BotBrowser] = [:]
    /// Agents' shells (`usual-bot` plugin), once a chat's terminal drawer asked about one.
    @ObservationIgnored var terminals: [Contact.ID: BotTerminal] = [:]
    let makeScreenSocket: ScreenSocketFactory
    /// Chats' messages ready to search (`searchMessages`).
    @ObservationIgnored let messageIndex = MessageIndex()
    /// Messages the gateway found in history this device hasn't loaded (`lookUpMessages`).
    let gatewaySearch = GatewaySearch()
    /// Counts finished room edits, so a room list read before one can't undo it.
    @ObservationIgnored var roomEdits = 0
    /// The demo has no gateway, so room edits happen here alone.
    @ObservationIgnored var isDemo = false
    #if DEBUG
        /// Shows the demo's other made-up gateway (`AppModel.demo()`), which nothing connects to.
        @ObservationIgnored var demoSwitch: ((SavedGateway) -> Void)?
    #endif
    /// Images and files agents name in chats, read from the gateway.
    @ObservationIgnored public private(set) lazy var media = MediaStore(
        auth: { [weak self] in self?.auth },
        chat: { [weak self] profile in
            self?.contacts.first { $0.kind == .agent && ($0.details?.profile ?? $0.id) == profile }?.chatID
        })
    @ObservationIgnored public private(set) lazy var voiceLive = VoiceLiveService(auth: { [weak self] in self?.auth })
    @ObservationIgnored public private(set) lazy var transcriber = GatewayTranscriber(
        auth: { [weak self] in self?.auth }, isDemo: { [weak self] in self?.isDemo ?? false })
    @ObservationIgnored public private(set) lazy var speaker = GatewaySpeaker(
        auth: { [weak self] in self?.auth }, isDemo: { [weak self] in self?.isDemo ?? false })
    /// How the gateway reaches you when this app can't.
    @ObservationIgnored public private(set) lazy var push = PushSettings(
        auth: { [weak self] in self?.auth }, relay: { [weak self] in self?.relay },
        gateway: { [weak self] in self?.activeGateway })
    /// This device's entry in Usual's push relay.
    @ObservationIgnored public internal(set) lazy var relay = PushRelay.fromMainBundle()
    /// A newer TestFlight build, in TestFlight builds; other builds never ask.
    @ObservationIgnored public private(set) lazy var update = AppUpdate.fromMainBundle()
    /// Token use across Bots, for Settings › Usage.
    @ObservationIgnored public internal(set) lazy var usage = UsageOverview(
        auth: { [weak self] in self?.auth },
        agents: { [weak self] in self?.contacts.filter { $0.kind == .agent } ?? [] })
    /// Each Bot's subscription limits, for Settings › Usage and rooms.
    @ObservationIgnored public internal(set) lazy var planLimits = PlanLimitOverview(
        channel: { [weak self] in self?.channel },
        agents: { [weak self] in self?.contacts.filter { $0.kind == .agent } ?? [] })
    /// Agents' own pictures from the official app; agents without one keep the app's characters.
    @ObservationIgnored public let pictures = BotPictures()
    /// How the sidebar is grouped.
    @ObservationIgnored public let sections: SidebarSections
    /// What's typed and not sent in each chat and room, on this device only.
    @ObservationIgnored public let drafts: Drafts
    /// What you shared from other apps, waiting for you to choose a chat for it.
    @ObservationIgnored public let shared: SharedInbox
    /// How far each Bot Chat was read, shared with your other devices through the gateway.
    @ObservationIgnored lazy var readSync: ReadSync = {
        let sync = ReadSync(auth: { [weak self] in self?.auth }, chats: { [weak self] in self?.readableChats ?? [] })
        sync.cleared = { [weak self] in self?.alertsCleared?($0) }
        return sync
    }()

    private static let rosterInterval: Duration = .seconds(5)
    /// Chats opening alongside the one on screen; see `attachChats`.
    static let backgroundOpens = 2
    private static let log = Logger(subsystem: "UsualBot", category: "app")

    public convenience init() {
        self.init(
            tokenStore: KeychainTokenStore.forApp(), http: URLSession.shared, defaults: .standard,
            cache: OfflineCache(), draftsDirectory: Drafts.deviceDirectory, share: .appGroup(),
            selectionDefaults: .standard)
    }

    /// Sends all gateway traffic, requests and the socket alike, through the session `session`
    /// returns at the time, e.g. one routed through the app's own Tailscale device.
    public convenience init(session: @escaping @Sendable () async throws -> URLSession) {
        self.init(
            tokenStore: KeychainTokenStore.forApp(), http: SessionTransport(session: session), defaults: .standard,
            cache: OfflineCache(), draftsDirectory: Drafts.deviceDirectory, share: .appGroup(),
            selectionDefaults: .standard, makeSocket: { URLSessionWebSocket(url: $0, session: try await session()) },
            makeScreenSocket: { URLSessionScreenSocket(url: $0, session: try await session()) })
    }

    init(
        tokenStore: any TokenStore, http: any HTTPTransport, defaults: UserDefaults, cache: OfflineCache,
        draftsDirectory: URL? = nil, share: ShareContainer? = nil, selectionDefaults: UserDefaults? = nil,
        makeSocket: @escaping GatewayConnector.SocketFactory = { URLSessionWebSocket(url: $0) },
        makeScreenSocket: @escaping ScreenSocketFactory = { URLSessionScreenSocket(url: $0) }
    ) {
        self.makeScreenSocket = makeScreenSocket
        self.tokenStore = tokenStore
        self.http = http
        self.defaults = defaults
        self.selectionDefaults = selectionDefaults ?? defaults
        let list = GatewayList(defaults: defaults)
        gatewayList = list
        self.cache = cache
        self.makeSocket = makeSocket
        sections = SidebarSections(defaults: defaults)
        drafts = Drafts(directory: draftsDirectory)
        shared = SharedInbox(container: share)
        let active = list.activeAddress
        gatewayInput = active?.baseURL.absoluteString ?? ""
        isRestoring = active != nil
        gateways = list.load()
        sections.save = { [weak self] profile, placement in
            guard let channel = self?.channel else { throw GatewayError.disconnected }
            try await BotMetaWrite.setSection(placement, profile: profile, on: channel)
        }
        sections.savePin = { [weak self] profile, isPinned in
            guard let channel = self?.channel else { throw GatewayError.disconnected }
            try await BotMetaWrite.setPinned(isPinned, profile: profile, on: channel)
        }
    }

    /// Resumes the saved session, if this device has one.
    public func restore() async {
        defer { isRestoring = false }
        guard case .signedOut = session, returnGatewayID == nil, let gateway = activeGateway?.address else { return }
        // Off the main thread: macOS can hold a Keychain read behind an access prompt, and the
        // window must stay responsive while it waits.
        let store = tokenStore
        let reading = Trace.begin("launch.keychain")
        let tokens = await Task.detached { try? store.load(for: gateway) }.value
        reading.end(tokens == nil ? "none" : "ok")
        guard case .signedOut = session, returnGatewayID == nil, let tokens else { return }
        let loading = Trace.begin("launch.cache")
        loadCache(for: gateway)
        loading.end("chats=\(threads.count)")
        Trace.first("launch.cached")
        begin(AuthSession(gateway: gateway, tokens: tokens, store: tokenStore, http: http))
    }

    /// Signs in to the gateway typed into `gatewayInput` through the browser.
    public func signIn(presenter: any SignInPresenter) {
        problem = nil
        let gateway: GatewayAddress
        do {
            gateway = try GatewayAddress(parsing: gatewayInput)
        } catch {
            problem = Self.describe(error)
            return
        }
        session = .signingIn(gateway)
        signInTask = Task {
            do {
                // Signing in again to a saved gateway that lost its sign-in is fine; a second
                // copy of one that has it, or a third gateway, isn't.
                let store = tokenStore
                let saved = gateways.first { $0.address == gateway }
                if saved != nil, await Task.detached(operation: { try? store.load(for: gateway) }).value != nil {
                    throw GatewayListError.alreadyConnected
                }
                if saved == nil, gateways.count >= Self.gatewayLimit { throw GatewayListError.full }
                let status = try await GatewayStatus.fetch(gateway, http: http)
                guard status.supportsNativeSignIn else { throw GatewayError.signInUnsupported }
                let tokens = try await NativeSignIn.run(gateway: gateway, http: http, presenter: presenter)
                try? tokenStore.save(tokens, for: gateway)
                if saved == nil { gateways.append(SavedGateway(address: gateway)) }
                gatewayList.save(gateways)
                gatewayList.activeAddress = gateway
                returnGatewayID = nil
                gatewayInput = gateway.baseURL.absoluteString
                if let saved { putBackRemembered(of: saved.id) } else { forgetRemembered() }
                loadCache(for: gateway)
                begin(AuthSession(gateway: gateway, tokens: tokens, store: tokenStore, http: http))
            } catch {
                if case .signingIn = session { session = .signedOut }
                if (error as? GatewayError) != .cancelled { problem = Self.describe(error, for: gateway) }
            }
        }
    }

    public func cancelSignIn() {
        signInTask?.cancel()
    }

    /// Drops the socket and connects again at once, e.g. after the route to the gateway changed.
    public func reconnect() {
        guard let auth else { return }
        connect(auth)
    }

    /// Signs out of the gateway in use, then goes on to the other one, if there is one.
    public func signOut() {
        guard let gone = activeGateway else {
            leave(forgetting: true)
            session = .signedOut
            return
        }
        alertsCleared?(nil)
        leave(forgetting: true)
        gateways.removeAll { $0.id == gone.id }
        gatewayList.save(gateways)
        if let next = gateways.first {
            activate(next)
        } else {
            gatewayList.activeAddress = nil
            forgetRemembered()
            session = .signedOut
        }
    }

    #if DEBUG
        /// The demo's way in (`AppModel.demo()`): shows this state as signed in and online without
        /// a gateway. Nothing connects, because there is no session to connect with.
        func showDemo(
            gateway: GatewayAddress, contacts: [Contact], threads: [Contact.ID: ChatThread],
            rooms: [Contact.ID: RoomThread], routines: [Contact.ID: RoutineList], skills: [Contact.ID: SkillList],
            vaults: [Contact.ID: VaultList], apps: [Contact.ID: MCPServerList]
        ) {
            isDemo = true
            session = .signedIn(gateway)
            link = .online(.canonical)
            self.contacts = contacts
            self.threads = threads
            self.rooms = rooms
            for (id, thread) in threads { wireAlerts(of: thread, id: id) }
            for (id, room) in rooms { wireAlerts(of: room, id: id) }
            routineLists = routines
            skillLists = skills
            vaultLists = vaults
            appLists = apps
            sections.save = { _, _ in }
            sections.savePin = { _, _ in }
            sections.reconcile(contacts)
            push.showDemo()
        }
    #endif

    // MARK: - Connection

    func begin(_ auth: AuthSession) {
        self.auth = auth
        session = .signedIn(auth.gateway)
        sections.load(for: auth.gateway)
        sections.reconcile(contacts)
        drafts.load(for: auth.gateway)
        connect(auth)
    }

    func connect(_ auth: AuthSession) {
        link = .connecting
        linkTask?.cancel()
        linkTask = isForeground || isCheckingIn ? Task { await stayConnected(auth) } : nil
    }

    /// On iPhone the app closes the socket when it goes to the background, where iOS would cut it
    /// anyway, and reconnects when it comes back; open chats reload from the gateway then.
    public func setForeground(_ foreground: Bool) {
        guard foreground != isForeground else { return }
        isForeground = foreground
        Trace.event(foreground ? "app.foreground" : "app.background", Trace.fields("link=\(link.traceName)"))
        resumedAt = foreground ? .now : nil
        showVisibleChat()
        guard let auth else { return }
        if !foreground { saveCache(for: auth.gateway) }
        // A notification woke the app, which connected (`warmUp`): you tapped it, so keep that link.
        if foreground, isCheckingIn, linkTask != nil {
            isCheckingIn = false
            attachVisibleChat()
            return
        }
        connect(auth)
    }

    /// Whether a chat is on screen. Not while the app is away: a chat that loads in the background,
    /// say for a notification, isn't read just because it was the one open when you left.
    func isShown(_ id: Contact.ID) -> Bool { isForeground && id == visibleContactID }

    private func showVisibleChat() {
        for (id, thread) in threads { thread.isVisible = isShown(id) }
        for (id, room) in rooms { room.isVisible = isShown(id) }
    }

    /// Connects, refreshes the roster every few seconds, and reconnects with backoff when the
    /// socket drops. Ends when the task is cancelled or the gateway rejects the session.
    private func stayConnected(_ auth: AuthSession) async {
        let connector = GatewayConnector(auth: auth, makeSocket: makeSocket)
        var attempt = 0
        let linkStarted = ContinuousClock.now
        var droppedAt: ContinuousClock.Instant?
        while !Task.isCancelled {
            do {
                let (channel, ready) = try await connector.connect(attempt: attempt)
                Trace.event(
                    "link.online",
                    Trace.fields(
                        "attempt=\(attempt)",
                        droppedAt.map { Trace.since($0, "offline_ms") } ?? Trace.since(linkStarted, "since_start_ms"),
                        Trace.since(resumedAt, "since_foreground_ms"), "dialect=\(ready.dialect.rawValue)"))
                droppedAt = nil
                attempt = 0
                Trace.first("launch.online")
                self.channel = channel
                replayEpoch = ready.replayEpoch?.stringValue
                for thread in threads.values { thread.replayEpoch = replayEpoch }
                link = .online(ready.dialect)
                readSync.reconnected()
                for screen in screens.values { screen.linkChanged() }
                let events = Task { for await event in channel.events { route(event) } }
                let requests = Task { for await request in channel.requests { await handle(request, on: channel) } }
                // The chat on screen is what you're waiting for: it doesn't wait for push settings or
                // the roster, the slowest read.
                let pushRefresh = Task { await push.refresh() }
                attachVisibleChat()
                defer {
                    pushRefresh.cancel()
                    events.cancel()
                    requests.cancel()
                    self.channel = nil
                    for thread in threads.values { thread.detach() }
                    Task { await channel.close() }
                }
                var firstRead = true
                while !Task.isCancelled {
                    let roster = Trace.begin("roster", firstRead ? "first=true" : "")
                    try await refreshRosterKeepingLink(on: channel)
                    roster.end(logging: firstRead || roster.elapsed >= 1000)
                    attachChats()
                    // Chats may have been read elsewhere while this link was down; after that, a
                    // chat that turns unread is looked at on the next read.
                    if firstRead { readSync.somethingChanged() } else { readSync.look() }
                    firstRead = false
                    saveCache(for: auth.gateway)
                    reportFocus()
                    try await Task.sleep(for: Self.rosterInterval)
                }
            } catch GatewayError.signInRequired {
                signInEnded(on: auth.gateway)
                return
            } catch {
                guard !Task.isCancelled else { return }
                link = .offline(Self.describe(error, for: auth.gateway))
                Self.log.error("Gateway link dropped: \(Self.describe(error), privacy: .public)")
                droppedAt = droppedAt ?? .now
                Trace.event(
                    "link.dropped",
                    "attempt=\(attempt) reason=\(Trace.reason(error)) retry_ms=\(Trace.milliseconds(Backoff.delay(attempt: attempt)))"
                )
                try? await Task.sleep(for: Backoff.delay(attempt: attempt))
                attempt += 1
                link = .connecting
            }
        }
    }

    // MARK: - Chats

    /// Contacts as the sidebar shows them: the roster plus each chat's live activity and unread count.
    /// A chat's newest message stands in for the roster's preview and time when it's newer, so the
    /// row moves as soon as you send and when the reply comes, not at the next roster refresh.
    public var sidebarContacts: [Contact] {
        contacts.map { contact in
            var contact = sections.placed(contact)
            if let thread = threads[contact.id] {
                contact.activity = thread.activity
                contact.unreadCount = thread.unreadCount
                contact.isMarkedUnread = thread.isMarkedUnread
                // The roster's preview would be this Bot's reply to another Bot.
                let items = thread.state.items
                if thread.turnIsForABot, let exchange = BotExchange.last(in: items) {
                    contact.preview = exchange.summary(running: thread.state.isRunning)
                    if let date = items[exchange.items].last(where: { $0.date != nil })?.date,
                        date > contact.lastActive ?? .distantPast
                    {
                        contact.lastActive = date
                    }
                } else if let newest = Self.newestMessage(in: items),
                    newest.date > contact.lastActive ?? .distantPast
                        || contact.preview.map(thread.state.isHiddenPreview) == true
                        || contact.preview == GatewayTurn.steerPreview
                {
                    contact.preview = newest.text
                    contact.lastActive = newest.date
                }
            } else if let room = rooms[contact.id] {
                contact.activity = room.activity
                contact.unreadCount = room.unreadCount
                contact.preview = room.preview ?? contact.preview
            }
            return contact
        }
    }

    /// A chat's newest message, yours or the agent's, as one plain line, and when it was said.
    private static func newestMessage(in items: [TranscriptItem]) -> (text: String, date: Date)? {
        for item in items.reversed() {
            switch item.content {
            case .user(let text), .assistant(let text):
                return item.date.map { (RoomThread.readable(text), $0) }
            default: continue
            }
        }
        return nil
    }

    /// The room behind a room contact.
    public func room(for contact: Contact) -> RoomThread? {
        rooms[contact.id]
    }

    /// The chat with `contact`. Call `openThread(for:)` to load it.
    public func thread(for contact: Contact) -> ChatThread {
        if let thread = threads[contact.id] { return thread }
        let thread = makeThread(contact.id, cached: nil)
        threads[contact.id] = thread
        return thread
    }

    func makeThread(_ id: Contact.ID, cached: CachedThread?) -> ChatThread {
        let thread = ChatThread(contactID: id, cached: cached, channel: { [weak self] in self?.channel })
        thread.isVisible = isShown(id)
        wireAlerts(of: thread, id: id)
        thread.storedAnswer = { [weak self] taskID in await self?.storedAnswer(taskID: taskID, profile: id) }
        thread.gateway = { [weak self] in self?.auth?.gateway }
        thread.replayEpoch = replayEpoch
        thread.wasRead = { [weak self] in self?.readSync.markRead(id) }
        thread.openEnded = { [weak self] in
            self?.traceOpened(id)
            self?.attachChats()
        }
        thread.gatewayIsUnencrypted = { [weak self] in self?.auth?.gateway.isUnencrypted ?? true }
        thread.chatOpened = { [weak self] sessionID in
            guard let self, !self.isDemo, let auth = self.auth else { return }
            Task { await UsualPlugin.noteChat(sessionID, on: auth) }
        }
        return thread
    }

    private func wireAlerts(of thread: ChatThread, id: Contact.ID) {
        thread.alert = { [weak self] in self?.heard($0, from: id) }
        thread.alertWithdrawn = { [weak self] in self?.alertWithdrawn?($0) }
        thread.backgroundTaskFinished = { [weak self] task, result in
            let alert = AgentAlert(
                id: UUID().uuidString, kind: .taskFinished, subtitle: task, preview: AgentAlert.plain(result))
            self?.heard(alert, from: id)
        }
        thread.goalEnded = { [weak self] goal, outcome in
            let alert = AgentAlert(
                id: UUID().uuidString, kind: .goalEnded, subtitle: goal,
                preview: outcome)
            self?.heard(alert, from: id)
        }
    }

    func wireAlerts(of room: RoomThread, id: Contact.ID) {
        room.alert = { [weak self] in self?.heard($0, from: id) }
        room.alertWithdrawn = { [weak self] in self?.alertWithdrawn?($0) }
    }

    private func heard(_ alert: AgentAlert, from id: Contact.ID) {
        guard let contact = contacts.first(where: { $0.id == id }) else { return }
        agentAlerted?(contact, alert)
    }

    /// Keeps every agent's existing Bot Chat attached, so its approvals reach this app and the
    /// sidebar shows when it's working. Agents without a Bot Chat get one only when you open them.
    /// The chat on screen opens at once and the rest `backgroundOpens` at a time: the gateway
    /// answers a socket's requests one by one and each open builds an agent, so opening every
    /// chat together left the last ones, and the roster read behind them, past their timeout.
    /// Opens the chat on screen from what the last roster said, before this link reads it again.
    func attachVisibleChat() {
        guard let visible = contacts.first(where: { $0.id == visibleContactID }),
            visible.kind == .agent, visible.chatID != nil
        else { return }
        openThread(for: visible)
    }

    func attachChats() {
        guard case .online = link else { return }
        let chats = contacts.filter { $0.kind == .agent && ($0.chatID != nil || threads[$0.id] != nil) }
        if let visible = chats.first(where: { $0.id == visibleContactID }) { openThread(for: visible) }
        let others = chats.filter { $0.id != visibleContactID }
        var opening = others.filter { threads[$0.id]?.isOpening == true }.count
        for contact in others where opening < Self.backgroundOpens && thread(for: contact).needsOpening {
            openThread(for: contact)
            opening += 1
        }
    }

    /// A background task's answer from its stored session (the task ID is its session ID), or
    /// `nil` while it runs or can't be read: the last stored message, when it's the agent's text.
    private func storedAnswer(taskID: String, profile: String) async -> String? {
        struct Row: Decodable {
            let role: String?
            let content: String?
            let toolCalls: JSONValue?
            let timestamp: Double?
        }
        struct Page: Decodable { let messages: [Row] }
        guard let auth else { return nil }
        let escape = { (text: String) in
            text.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? text
        }
        guard
            let page = try? await auth.json(
                Page.self,
                path:
                    "/api/sessions/\(escape(taskID))/messages?profile=\(escape(profile))&order=latest&limit=5&inline_images=false"
            ),
            let last = page.messages.max(by: { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }),
            last.role == "assistant", last.toolCalls == nil || last.toolCalls == .array([]) || last.toolCalls == .null,
            let text = last.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }

    /// Finds or creates the agent's Bot Chat and loads it, once the link is online.
    public func openThread(for contact: Contact) {
        guard case .online(let dialect) = link else { return }
        thread(for: contact).open(knownID: contact.chatID, dialect: dialect)
    }

    // MARK: - Profile panel

    /// The routines of `contact`'s profile. Call `RoutineList.refresh()` to load them.
    public func routines(for contact: Contact) -> RoutineList {
        if let list = routineLists[contact.id] { return list }
        let list = RoutineList(profile: contact.details?.profile ?? contact.id, auth: { [weak self] in self?.auth })
        routineLists[contact.id] = list
        return list
    }

    /// The skills of `contact`'s profile. Call `SkillList.refresh()` to load them.
    public func skills(for contact: Contact) -> SkillList {
        if let list = skillLists[contact.id] { return list }
        let list = SkillList(profile: contact.details?.profile ?? contact.id, auth: { [weak self] in self?.auth })
        skillLists[contact.id] = list
        return list
    }

    /// The vault of `contact`'s profile. Call `VaultList.refresh()` to load it.
    public func vault(for contact: Contact) -> VaultList {
        if let list = vaultLists[contact.id] { return list }
        let list = VaultList(
            profile: contact.details?.profile ?? contact.id, channel: { [weak self] in self?.channel },
            gatewayIsUnencrypted: { [weak self] in self?.auth?.gateway.isUnencrypted ?? true })
        vaultLists[contact.id] = list
        return list
    }

    /// The MCP servers ("apps") of `contact`'s profile. Call `MCPServerList.refresh()` to load them.
    public func apps(for contact: Contact) -> MCPServerList {
        if let list = appLists[contact.id] { return list }
        let list = MCPServerList(
            profile: contact.details?.profile ?? contact.id, auth: { [weak self] in self?.auth },
            channel: { [weak self] in self?.channel },
            sessionID: { [weak self] in self?.threads[contact.id]?.sessionID },
            gatewayIsUnencrypted: { [weak self] in self?.auth?.gateway.isUnencrypted ?? true })
        appLists[contact.id] = list
        return list
    }

    /// The apps `contact`'s profile connects through the Nous Portal. Call `ConnectorList.refresh()`.
    public func connectors(for contact: Contact) -> ConnectorList {
        if let list = connectorLists[contact.id] { return list }
        let list = ConnectorList(
            profile: contact.details?.profile ?? contact.id, channel: { [weak self] in self?.channel })
        #if DEBUG
            if isDemo { list.showDemo(DemoConnections.connectors) }
        #endif
        connectorLists[contact.id] = list
        return list
    }

    /// Loads what the Machine tab shows. Parts the gateway doesn't answer stay empty.
    public func loadGatewayDetails() async {
        guard let auth else { return }
        let status = try? await GatewayStatus.fetch(auth.gateway, http: http)
        let user = try? await auth.json(SignedInUser.self, path: "/api/auth/me")
        gatewayDetails = GatewayDetails(
            version: status?.version, isHealthy: status?.overall.map { $0 == "ok" }, account: user?.label)
    }

    /// Hands an event to the chat whose live session it belongs to.
    private func route(_ event: GatewayEvent) {
        if event.type == "cron.changed" {
            // Jobs changed somewhere on the gateway: reload the lists that are loaded.
            for list in routineLists.values where list.phase == .ready { Task { await list.refresh() } }
            return
        }
        if event.type == "sessions.changed" {
            // Says only that some conversation changed, perhaps a read elsewhere.
            readSync.somethingChanged()
            return
        }
        if event.type.hasPrefix("display.") {
            for screen in screens.values { screen.apply(event) }
            return
        }
        guard let sessionID = event.sessionID,
            let thread = threads.values.first(where: { $0.sessionID == sessionID })
        else { return }
        thread.apply(event)
    }

    /// Answers the gateway's questions: approvals, clarify questions and masked prompts go to their
    /// chat. Masked prompts with no chat to show them are skipped, never declined: the only app
    /// declining settles the request with error text, which the gateway takes for the answer.
    /// Anything else is declined as "not shown here" (4404): the gateway then lets another attached
    /// app, such as the official one, answer, and gives up at once when no app can, so the agent
    /// never waits on Usual Bot. On the canonical protocol any answer settles a request for every
    /// app, a skip included, so a request with no chat here gets none.
    private func handle(_ request: ServerRequest, on channel: JSONRPCChannel) async {
        let thread = threads.values.first { $0.sessionID != nil && $0.sessionID == request.sessionID }
        defer { thread?.announceRequests() }
        let skips = await channel.dialect == .legacy
        if VaultPrompt.methods.contains(request.method) {
            if let thread, let prompt = VaultPrompt(request) {
                thread.receive(prompt)
            } else if skips {
                await channel.respond(to: request.id, result: VaultPrompt.skipped)
            }
            return
        }
        if let thread, let approval = ApprovalPrompt(request) {
            thread.receive(approval)
            return
        }
        if let thread, let prompt = ClarifyPrompt(request) {
            thread.receive(prompt)
            return
        }
        if SecretPrompt.methods.contains(request.method) {
            // Never 4404: when no other app is attached, the gateway answers a decline with a JSON
            // error as the value, and would save that as the secret. An empty value is a skip.
            if let thread, let prompt = SecretPrompt(request) {
                thread.receive(prompt)
            } else if skips {
                await channel.respond(to: request.id, result: ["value": ""])
            }
            return
        }
        await channel.decline(
            request.id, code: 4404, message: "Usual Bot can't answer “\(request.method)” requests.")
    }

    /// Writes the roster and recent messages for next launch, when they changed.
    func saveCache(for gateway: GatewayAddress) {
        let built = Trace.begin("cache.save")
        let snapshot = OfflineCache.Snapshot(
            contacts: contacts, threads: threads.filter { $0.value.phase == .ready }.mapValues(\.cacheEntry),
            pictures: pictures.stored)
        guard snapshot != lastSaved else { return built.end(logging: false) }
        // On the main actor, every few seconds while something changes: worth seeing when it's slow.
        defer { built.end("chats=\(snapshot.threads.count)") }
        do {
            try cache.save(snapshot, for: gateway)
            lastSaved = snapshot
        } catch {
            Self.log.error("Couldn't save the offline cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads the roster, and skips a read that timed out while the link is still open: a slow
    /// gateway answering other requests first isn't a dead link, and dropping it would open every
    /// chat again. A silent link closes itself (`JSONRPCChannel`'s heartbeat).
    func refreshRosterKeepingLink(on channel: JSONRPCChannel, timeout: Duration = .seconds(30)) async throws {
        do {
            try await refreshRoster(on: channel, timeout: timeout)
        } catch GatewayError.timedOut {
            guard await channel.isOpen else { throw GatewayError.timedOut }
            Self.log.notice("The roster read timed out; keeping the link")
        }
    }

    func refreshRoster(on channel: JSONRPCChannel, timeout: Duration = .seconds(30)) async throws {
        let result = try await channel.call("profiles.list", params: ["include_sessions": true], timeout: timeout)
        let list = try result.decode(ProfileList.self)
        followProfileChanges(list.profiles)
        let all = rosterHolds.apply(to: list.profiles.map(Contact.init(profile:)))
        let hidden = rosterHolds.hidden(among: all, reported: Set(list.profiles.filter(\.isHidden).map(\.name)))
        pictures.refresh(all, on: channel)
        hiddenBots = all.filter { hidden.contains($0.id) }
        let agents = all.filter { !hidden.contains($0.id) }
        contacts = agents + (await refreshRooms(on: channel) ?? contacts.filter { $0.kind != .agent })
        sections.reconcile(contacts)
        rosterReads += 1
    }
}
