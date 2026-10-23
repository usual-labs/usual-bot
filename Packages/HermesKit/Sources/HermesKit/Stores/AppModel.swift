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
    public private(set) var contacts: [Contact] = []
    /// The chat on screen, if any. Its replies don't count as unread.
    public var visibleContactID: Contact.ID? {
        didSet {
            for (id, thread) in threads { thread.isVisible = id == visibleContactID }
            for (id, room) in rooms { room.isVisible = id == visibleContactID }
        }
    }
    /// Version, health and account, once the Machine tab asked for them.
    public private(set) var gatewayDetails: GatewayDetails?
    /// The last sign-in or connection problem, for the connect screen.
    public private(set) var problem: String?
    /// What the user last typed into the gateway field.
    public var gatewayInput: String

    private let tokenStore: any TokenStore
    private let http: any HTTPTransport
    private let makeSocket: GatewayConnector.SocketFactory
    private let defaults: UserDefaults
    private let cache: OfflineCache
    @ObservationIgnored private var lastSaved: OfflineCache.Snapshot?
    private var auth: AuthSession?
    private var signInTask: Task<Void, Never>?
    private var linkTask: Task<Void, Never>?
    /// The socket while the link is online.
    @ObservationIgnored private var channel: JSONRPCChannel?
    @ObservationIgnored private var threads: [Contact.ID: ChatThread] = [:]
    @ObservationIgnored private var routineLists: [Contact.ID: RoutineList] = [:]
    @ObservationIgnored private var rooms: [Contact.ID: RoomThread] = [:]

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
        gatewayInput = defaults.string(forKey: Self.gatewayKey) ?? ""
    }

    /// Resumes the saved session, if this device has one.
    public func restore() async {
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
                if (error as? GatewayError) != .cancelled { problem = Self.describe(error) }
            }
        }
    }

    public func cancelSignIn() {
        signInTask?.cancel()
    }

    public func signOut() {
        linkTask?.cancel()
        signInTask?.cancel()
        if let auth {
            cache.delete(for: auth.gateway)
            Task { await auth.signOut() }
        }
        auth = nil
        contacts = []
        threads = [:]
        routineLists = [:]
        rooms = [:]
        gatewayDetails = nil
        lastSaved = nil
        link = .connecting
        session = .signedOut
    }

    // MARK: - Connection

    private func begin(_ auth: AuthSession) {
        self.auth = auth
        session = .signedIn(auth.gateway)
        link = .connecting
        linkTask?.cancel()
        linkTask = Task { await stayConnected(auth) }
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
                link = .online(ready.dialect)
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
                    try await Task.sleep(for: Self.rosterInterval)
                }
            } catch GatewayError.signInRequired {
                problem = GatewayError.signInRequired.errorDescription
                signOut()
                return
            } catch {
                guard !Task.isCancelled else { return }
                link = .offline(Self.describe(error))
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
            var contact = contact
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
        return thread
    }

    /// Keeps every agent's existing Bot Chat attached, so its approvals reach this app and the
    /// sidebar shows when it's working. Agents without a Bot Chat get one only when you open them.
    private func attachChats() {
        for contact in contacts where contact.kind == .agent && (contact.chatID != nil || threads[contact.id] != nil) {
            openThread(for: contact)
        }
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

    /// Answers the gateway's questions: approvals and clarify questions go to their chat. Anything else is declined as
    /// "not shown here" (4404): the gateway then lets another attached app, such as the official
    /// one, answer, and gives up at once when no app can, so the agent never waits on Usual Bot.
    private func handle(_ request: ServerRequest, on channel: JSONRPCChannel) async {
        let thread = threads.values.first { $0.sessionID != nil && $0.sessionID == request.sessionID }
        if let thread, let approval = ApprovalPrompt(request) {
            thread.receive(approval)
            return
        }
        if let thread, let prompt = ClarifyPrompt(request) {
            thread.receive(prompt)
            return
        }
        await channel.decline(
            request.id, code: 4404, message: "Usual Bot can't answer “\(request.method)” requests.")
    }

    /// Writes the roster and recent messages for next launch, when they changed.
    private func saveCache(for gateway: GatewayAddress) {
        let snapshot = OfflineCache.Snapshot(
            contacts: contacts, threads: threads.filter { $0.value.phase == .ready }.mapValues(\.cacheEntry))
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
        contacts = agents + (await refreshRooms(on: channel) ?? contacts.filter { $0.kind != .agent })
    }

    /// Lists the gateway's rooms and catches up any that have new events. Returns `nil` when the
    /// gateway couldn't list them, so the sidebar keeps the rooms it had.
    private func refreshRooms(on channel: JSONRPCChannel) async -> [Contact]? {
        guard let result = try? await channel.call("groups.list", params: ["limit": 200]),
            case .array(let rows) = result["rooms"]
        else { return nil }
        let summaries = rows.compactMap(RoomSummary.init)
        var listed: [Contact.ID: RoomThread] = [:]
        for summary in summaries {
            let room = roomThread(for: summary)
            listed[RoomSummary.contactID(summary.id)] = room
            if summary.latestSeq > room.cursor || room.phase != .ready { Task { await room.sync() } }
        }
        rooms = listed
        return summaries.map(Contact.init(room:))
    }

    /// The room behind `summary`, kept across refreshes so its transcript stays loaded.
    private func roomThread(for summary: RoomSummary) -> RoomThread {
        let id = RoomSummary.contactID(summary.id)
        let room = rooms[id] ?? RoomThread(summary: summary, channel: { [weak self] in self?.channel })
        room.update(summary)
        room.isVisible = id == visibleContactID
        return room
    }

    /// Creates a room with `agents`, two to six of this gateway's agents, and lists it at once.
    /// Returns the room's contact ID, to open it.
    public func createRoom(named name: String, agents: [Contact]) async throws -> Contact.ID {
        guard let channel else { throw GatewayError.disconnected }
        let summary = try await RoomThread.create(
            named: name, profiles: agents.map { $0.details?.profile ?? $0.id }, on: channel)
        let contact = Contact(room: summary)
        let room = roomThread(for: summary)
        rooms[contact.id] = room
        contacts.removeAll { $0.id == contact.id }
        contacts.append(contact)
        Task { await room.sync() }
        return contact.id
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as GatewayAddress.ParseError:
            switch error {
            case .empty: return String(localized: "Enter your gateway's address.")
            case .invalid: return String(localized: "That doesn't look like a gateway address.")
            case .insecureHTTP(let host):
                return String(
                    localized: "\(host) is on the public internet, so use https:// to keep your sign-in private.")
            }
        case let error as GatewayError:
            return error.errorDescription ?? String(describing: error)
        default:
            return error.localizedDescription
        }
    }
}
