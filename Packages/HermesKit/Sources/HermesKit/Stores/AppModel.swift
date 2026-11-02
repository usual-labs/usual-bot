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

    public private(set) var session: Session = .signedOut
    public private(set) var link: Link = .connecting
    /// The agents and rooms the gateway reports, in its own terms. Show `sidebarContacts` instead.
    public internal(set) var contacts: [Contact] = []
    /// The chat on screen, if any. Its replies don't count as unread.
    public var visibleContactID: Contact.ID? {
        didSet {
            for (id, thread) in threads { thread.isVisible = id == visibleContactID }
            for (id, room) in rooms { room.isVisible = id == visibleContactID }
            if let visibleContactID { alertsCleared?(visibleContactID) }
        }
    }
    /// A chat to open, say because you tapped its notification. The window clears it.
    public var requestedContactID: Contact.ID?
    /// Version, health and account, once the Machine tab asked for them.
    public private(set) var gatewayDetails: GatewayDetails?
    /// The last sign-in or connection problem, for the connect screen.
    public private(set) var problem: String?
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

    private let tokenStore: any TokenStore
    private let http: any HTTPTransport
    private let makeSocket: GatewayConnector.SocketFactory
    private let defaults: UserDefaults
    private let cache: OfflineCache
    @ObservationIgnored private var lastSaved: OfflineCache.Snapshot?
    var auth: AuthSession?
    private var signInTask: Task<Void, Never>?
    var linkTask: Task<Void, Never>?
    /// Whether the app is on screen; the socket stays closed while it isn't.
    var isForeground = true
    /// iOS gave the app a moment in the background (`checkIn()`).
    var isCheckingIn = false
    /// Counts roster reads, so `checkIn()` knows when this link has read the gateway.
    @ObservationIgnored var rosterReads = 0
    /// The socket while the link is online.
    @ObservationIgnored var channel: JSONRPCChannel?
    /// The gateway process's event numbering, for replaying what a short drop missed.
    @ObservationIgnored private var replayEpoch: String?
    @ObservationIgnored var threads: [Contact.ID: ChatThread] = [:]
    @ObservationIgnored private var routineLists: [Contact.ID: RoutineList] = [:]
    @ObservationIgnored private var skillLists: [Contact.ID: SkillList] = [:]
    @ObservationIgnored private var vaultLists: [Contact.ID: VaultList] = [:]
    @ObservationIgnored private var appLists: [Contact.ID: MCPServerList] = [:]
    @ObservationIgnored var rooms: [Contact.ID: RoomThread] = [:]
    /// Chats' messages ready to search (`searchMessages`).
    @ObservationIgnored let messageIndex = MessageIndex()
    /// Counts finished room edits, so a room list read before one can't undo it.
    @ObservationIgnored var roomEdits = 0
    /// The demo has no gateway, so room edits happen here alone.
    @ObservationIgnored var isDemo = false
    /// Images and files agents name in chats, read from the gateway.
    @ObservationIgnored public private(set) lazy var media = MediaStore(auth: { [weak self] in self?.auth })
    @ObservationIgnored public private(set) lazy var voiceLive = VoiceLiveService(auth: { [weak self] in self?.auth })
    /// How the gateway reaches you when this app can't.
    @ObservationIgnored public private(set) lazy var push = PushSettings(auth: { [weak self] in self?.auth })
    /// Agents' own pictures from the official app; agents without one keep the app's characters.
    @ObservationIgnored public let pictures = BotPictures()
    /// How the sidebar is grouped.
    @ObservationIgnored public let sections: SidebarSections

    private static let gatewayKey = "gatewayAddress"
    private static let rosterInterval: Duration = .seconds(5)
    private static let log = Logger(subsystem: "UsualBot", category: "app")

    public convenience init() {
        self.init(tokenStore: KeychainTokenStore(), http: URLSession.shared, defaults: .standard, cache: OfflineCache())
    }

    init(
        tokenStore: any TokenStore, http: any HTTPTransport, defaults: UserDefaults, cache: OfflineCache,
        makeSocket: @escaping GatewayConnector.SocketFactory = { URLSessionWebSocket(url: $0) }
    ) {
        self.tokenStore = tokenStore
        self.http = http
        self.defaults = defaults
        self.cache = cache
        self.makeSocket = makeSocket
        sections = SidebarSections(defaults: defaults)
        gatewayInput = defaults.string(forKey: Self.gatewayKey) ?? ""
        isRestoring = defaults.string(forKey: Self.gatewayKey) != nil
        sections.save = { [weak self] profile, placement in
            guard let channel = self?.channel else { throw GatewayError.disconnected }
            try await BotMetaWrite.setSection(placement, profile: profile, on: channel)
        }
    }

    /// Resumes the saved session, if this device has one.
    public func restore() async {
        defer { isRestoring = false }
        guard case .signedOut = session,
            let saved = defaults.string(forKey: Self.gatewayKey),
            let gateway = try? GatewayAddress(parsing: saved)
        else { return }
        // Off the main thread: macOS can hold a Keychain read behind an access prompt, and the
        // window must stay responsive while it waits.
        let store = tokenStore
        let tokens = await Task.detached { try? store.load(for: gateway) }.value
        guard case .signedOut = session, let tokens else { return }
        if let snapshot = cache.load(for: gateway) {
            contacts = snapshot.contacts
            threads = snapshot.threads.reduce(into: [:]) { threads, entry in
                threads[entry.key] = makeThread(entry.key, cached: entry.value)
            }
            pictures.restore(snapshot.pictures ?? [:])
            lastSaved = snapshot
        }
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
                let status = try await GatewayStatus.fetch(gateway, http: http)
                guard status.supportsNativeSignIn else { throw GatewayError.signInUnsupported }
                let tokens = try await NativeSignIn.run(gateway: gateway, http: http, presenter: presenter)
                try? tokenStore.save(tokens, for: gateway)
                defaults.set(gateway.baseURL.absoluteString, forKey: Self.gatewayKey)
                gatewayInput = gateway.baseURL.absoluteString
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

    public func signOut() {
        linkTask?.cancel()
        signInTask?.cancel()
        alertsCleared?(nil)
        if let auth {
            cache.delete(for: auth.gateway)
            Task { await auth.signOut() }
        }
        auth = nil
        contacts = []
        threads = [:]
        routineLists = [:]
        skillLists = [:]
        vaultLists = [:]
        appLists = [:]
        media.clear()
        pictures.clear()
        sections.clear()
        push.clear()
        rooms = [:]
        gatewayDetails = nil
        lastSaved = nil
        link = .connecting
        session = .signedOut
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
            link = .online(.legacy)
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
            sections.reconcile(contacts)
            push.showDemo()
        }
    #endif

    // MARK: - Connection

    private func begin(_ auth: AuthSession) {
        self.auth = auth
        session = .signedIn(auth.gateway)
        sections.load(for: auth.gateway)
        sections.reconcile(contacts)
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
        guard let auth else { return }
        if !foreground { saveCache(for: auth.gateway) }
        connect(auth)
    }

    /// Connects, refreshes the roster every few seconds, and reconnects with backoff when the
    /// socket drops. Ends when the task is cancelled or the gateway rejects the session.
    private func stayConnected(_ auth: AuthSession) async {
        let connector = GatewayConnector(auth: auth, makeSocket: makeSocket)
        var attempt = 0
        while !Task.isCancelled {
            do {
                let (channel, ready) = try await connector.connect()
                attempt = 0
                self.channel = channel
                replayEpoch = ready.replayEpoch?.stringValue
                for thread in threads.values { thread.replayEpoch = replayEpoch }
                link = .online(ready.dialect)
                await push.refresh()
                let events = Task { for await event in channel.events { route(event) } }
                let requests = Task { for await request in channel.requests { await handle(request, on: channel) } }
                defer {
                    events.cancel()
                    requests.cancel()
                    self.channel = nil
                    for thread in threads.values { thread.detach() }
                    Task { await channel.close() }
                }
                while !Task.isCancelled {
                    try await refreshRoster(on: channel)
                    attachChats()
                    saveCache(for: auth.gateway)
                    reportFocus()
                    try await Task.sleep(for: Self.rosterInterval)
                }
            } catch GatewayError.signInRequired {
                problem = GatewayError.signInRequired.errorDescription
                signOut()
                return
            } catch {
                guard !Task.isCancelled else { return }
                link = .offline(Self.describe(error, for: auth.gateway))
                Self.log.error("Gateway link dropped: \(Self.describe(error), privacy: .public)")
                try? await Task.sleep(for: Backoff.delay(attempt: attempt))
                attempt += 1
                link = .connecting
            }
        }
    }

    // MARK: - Chats

    /// Contacts as the sidebar shows them: the roster plus each chat's live activity and unread count.
    public var sidebarContacts: [Contact] {
        contacts.map { contact in
            var contact = sections.placed(contact)
            if let thread = threads[contact.id] {
                contact.activity = thread.activity
                contact.unreadCount = thread.unreadCount
            } else if let room = rooms[contact.id] {
                contact.activity = room.activity
                contact.unreadCount = room.unreadCount
                contact.preview = room.preview ?? contact.preview
            }
            return contact
        }
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

    private func makeThread(_ id: Contact.ID, cached: CachedThread?) -> ChatThread {
        let thread = ChatThread(contactID: id, cached: cached, channel: { [weak self] in self?.channel })
        thread.isVisible = id == visibleContactID
        wireAlerts(of: thread, id: id)
        thread.storedAnswer = { [weak self] taskID in await self?.storedAnswer(taskID: taskID, profile: id) }
        thread.gateway = { [weak self] in self?.auth?.gateway }
        thread.replayEpoch = replayEpoch
        thread.gatewayIsUnencrypted = { [weak self] in self?.auth?.gateway.isUnencrypted ?? true }
        return thread
    }

    private func wireAlerts(of thread: ChatThread, id: Contact.ID) {
        thread.alert = { [weak self] in self?.heard($0, from: id) }
        thread.alertWithdrawn = { [weak self] in self?.alertWithdrawn?($0) }
        thread.backgroundTaskFinished = { [weak self] task, result in
            self?.heard(.init(id: UUID().uuidString, kind: .taskFinished, subtitle: task, preview: result), from: id)
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
    private func attachChats() {
        for contact in contacts where contact.kind == .agent && (contact.chatID != nil || threads[contact.id] != nil) {
            openThread(for: contact)
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
    /// never waits on Usual Bot.
    private func handle(_ request: ServerRequest, on channel: JSONRPCChannel) async {
        let thread = threads.values.first { $0.sessionID != nil && $0.sessionID == request.sessionID }
        defer { thread?.announceRequests() }
        if VaultPrompt.methods.contains(request.method) {
            if let thread, let prompt = VaultPrompt(request) {
                thread.receive(prompt)
            } else {
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
            } else {
                await channel.respond(to: request.id, result: ["value": ""])
            }
            return
        }
        await channel.decline(
            request.id, code: 4404, message: "Usual Bot can't answer “\(request.method)” requests.")
    }

    /// Writes the roster and recent messages for next launch, when they changed.
    func saveCache(for gateway: GatewayAddress) {
        let snapshot = OfflineCache.Snapshot(
            contacts: contacts, threads: threads.filter { $0.value.phase == .ready }.mapValues(\.cacheEntry),
            pictures: pictures.stored)
        guard snapshot != lastSaved else { return }
        do {
            try cache.save(snapshot, for: gateway)
            lastSaved = snapshot
        } catch {
            Self.log.error("Couldn't save the offline cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshRoster(on channel: JSONRPCChannel) async throws {
        let result = try await channel.call("profiles.list", params: ["include_sessions": true])
        let list = try result.decode(ProfileList.self)
        let agents = list.profiles.compactMap(Contact.init(profile:))
        pictures.refresh(agents, on: channel)
        contacts = agents + (await refreshRooms(on: channel) ?? contacts.filter { $0.kind != .agent })
        sections.reconcile(contacts)
        rosterReads += 1
    }
}
