import Foundation

/// More than one gateway: one in use at a time, the others signed in but disconnected. Switching
/// keeps everything this device holds for the one you leave (sign-in, cached chats, drafts,
/// sidebar), so coming back shows it straight away.
extension AppModel {
    /// The most gateways one device signs in to.
    public static let gatewayLimit = 2
    /// The window's open chat, in `@AppStorage`.
    public static let selectedContactKey = "selectedContact"
    /// Quick Message's chosen Bot, in `@AppStorage`.
    public static let quickRecipientKey = "quickRecipient"
    /// What each gateway remembers for when you come back. Bare chat IDs: each gateway has a `default`.
    static let rememberedKeys = [selectedContactKey, quickRecipientKey]

    /// The gateway in use, or about to be.
    public var activeGateway: SavedGateway? {
        guard let address = gatewayList.activeAddress else { return nil }
        return gateways.first { $0.address == address }
    }

    public var canAddGateway: Bool { gateways.count < Self.gatewayLimit }

    /// Disconnects from the gateway in use and goes to `id`, from its cache while it connects.
    public func switchTo(_ id: SavedGateway.ID) {
        guard let next = gateways.first(where: { $0.id == id }) else { return }
        if returnGatewayID != nil {
            signInTask?.cancel()
            returnGatewayID = nil
        } else {
            guard next.id != activeGateway?.id || !isSignedIn else { return }
            leave(forgetting: false)
        }
        activate(next)
    }

    /// Leaves the gateway in use for the connect screen, which then offers Cancel to go back.
    public func addGateway() {
        guard canAddGateway, let current = activeGateway, returnGatewayID == nil else { return }
        leave(forgetting: false)
        returnGatewayID = current.id
        problem = nil
        gatewayInput = ""
        session = .signedOut
    }

    /// Back to the gateway you were using before Add Gateway.
    public func cancelAddingGateway() {
        guard let id = returnGatewayID else { return }
        switchTo(id)
    }

    /// The name this device shows for a gateway; empty goes back to its host.
    public func rename(_ id: SavedGateway.ID, to name: String) {
        guard let index = gateways.firstIndex(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank
        guard gateways[index].name != name else { return }
        gateways[index].name = name
        gatewayList.save(gateways)
    }

    /// Whether the gateway in use notifies this device. Off takes the device off its push list.
    public func setNotifications(_ on: Bool) async {
        guard let index = gateways.firstIndex(where: { $0.id == activeGateway?.id }) else { return }
        gateways[index].notifies = on
        gatewayList.save(gateways)
        if !on, let auth { await push.forget(on: auth) }
        await push.refresh()
    }

    /// The gateway in use answers notifications only with what the push plugin sealed for it, but
    /// with two gateways an older plugin's say nothing about which gateway sent them.
    public var pushPluginNeedsUpdate: Bool {
        gateways.count > 1 && push.phase == .ready && !push.tagsGateway
    }

    /// The app's word on which gateways have notifications waiting, from what it shows.
    public func showNews(on ids: Set<SavedGateway.ID>) {
        #if DEBUG
            if isDemo { return }
        #endif
        let news = ids.subtracting([activeGateway?.id].compactMap(\.self))
        if news != gatewaysWithNews { gatewaysWithNews = news }
    }

    // MARK: - Internals

    /// Shows `saved` from its cache, then connects once its sign-in is read.
    func activate(_ saved: SavedGateway) {
        let gateway = saved.address
        gatewayList.activeAddress = gateway
        gatewayInput = gateway.baseURL.absoluteString
        problem = nil
        putBackRemembered(of: saved.id)
        #if DEBUG
            if isDemo {
                demoSwitch?(saved)
                return
            }
        #endif
        loadCache(for: gateway)
        session = .signedIn(gateway)
        link = .connecting
        sections.load(for: gateway)
        sections.reconcile(contacts)
        drafts.load(for: gateway)
        let store = tokenStore
        signInTask = Task {
            let tokens = await Task.detached { try? store.load(for: gateway) }.value
            guard !Task.isCancelled, auth == nil, activeGateway?.id == saved.id else { return }
            guard let tokens else { return signInEnded(on: gateway) }
            begin(AuthSession(gateway: gateway, tokens: tokens, store: tokenStore, http: http))
        }
    }

    /// The gateway wants you to sign in again: it's forgotten here, and the connect screen asks,
    /// with Cancel going to the other gateway if there is one.
    func signInEnded(on gateway: GatewayAddress) {
        let other = gateways.first { $0.address != gateway }
        alertsCleared?(nil)
        leave(forgetting: true)
        gateways.removeAll { $0.address == gateway }
        gatewayList.save(gateways)
        gatewayList.activeAddress = other?.address
        if other == nil { forgetRemembered() }
        returnGatewayID = other?.id
        session = .signedOut
        problem = GatewayError.signInRequired.errorDescription
        gatewayInput = gateway.baseURL.absoluteString
    }

    /// Reads what this device kept for `gateway` from its last connection.
    func loadCache(for gateway: GatewayAddress) {
        guard let snapshot = cache.load(for: gateway) else { return }
        contacts = snapshot.contacts
        threads = snapshot.threads.reduce(into: [:]) { threads, entry in
            threads[entry.key] = makeThread(entry.key, cached: entry.value)
        }
        pictures.restore(snapshot.pictures ?? [:])
        lastSaved = snapshot
    }

    /// Lets go of the gateway in use: disconnects and empties what's shown. `forgetting` also
    /// deletes what this device kept for it and signs out; otherwise it's saved for coming back.
    func leave(forgetting: Bool) {
        linkTask?.cancel()
        linkTask = nil
        signInTask?.cancel()
        if let auth {
            if forgetting {
                cache.delete(for: auth.gateway)
                // Off the gateway's push list first, while the sign-in still works.
                Task { [push] in
                    await push.forget(on: auth)
                    await auth.signOut()
                }
            } else {
                saveCache(for: auth.gateway)
                drafts.save()
                // Or it goes on thinking you're reading the chat you left, and never notifies about it.
                if push.isActive { Task { [push] in await push.reportNoneOpen(on: auth) } }
            }
        }
        if !forgetting, let id = activeGateway?.id { rememberSelection(for: id) }
        auth = nil
        readSync.reset()
        contacts = []
        hiddenBots = []
        threads = [:]
        routineLists = [:]
        skillLists = [:]
        vaultLists = [:]
        appLists = [:]
        connectorLists = [:]
        rosterHolds = RosterHolds()
        renamedAgents = [:]
        media.clear()
        pictures.clear()
        if forgetting {
            sections.clear()
            drafts.clear()
            if let gateway = activeGateway?.address { shared.clear(gateway: gateway.fileName) }
        } else {
            sections.unload()
            drafts.unload()
            shared.unload()
        }
        push.clear()
        usage.clear()
        rooms = [:]
        messageIndex.keep(only: [])
        gatewaySearch.reset()
        for screen in screens.values { screen.disconnect() }
        screens = [:]
        for browser in browsers.values { browser.disconnect() }
        browsers = [:]
        gatewayDetails = nil
        lastSaved = nil
        visibleContactID = nil
        link = .connecting
    }

    private func rememberSelection(for id: SavedGateway.ID) {
        guard let index = gateways.firstIndex(where: { $0.id == id }) else { return }
        gateways[index].remembered = Dictionary(
            uniqueKeysWithValues: Self.rememberedKeys.compactMap { key in
                selectionDefaults.string(forKey: key).map { (key, $0) }
            })
        gatewayList.save(gateways)
    }

    /// Puts back what was open on `id`, so the window opens its chat, not another gateway's.
    func putBackRemembered(of id: SavedGateway.ID) {
        let remembered = gateways.first { $0.id == id }?.remembered ?? [:]
        for key in Self.rememberedKeys { selectionDefaults.set(remembered[key], forKey: key) }
    }

    func forgetRemembered() {
        for key in Self.rememberedKeys { selectionDefaults.removeObject(forKey: key) }
    }
}

enum GatewayListError: LocalizedError {
    case alreadyConnected
    case full

    var errorDescription: String? {
        switch self {
        case .alreadyConnected: String(localized: "You’re already connected to this gateway.")
        case .full: String(localized: "Usual Bot connects to two gateways at most.")
        }
    }
}
