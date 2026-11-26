import Foundation

/// What keeps iPhone notifications going once the app has left the screen.
extension AppModel {
    /// Tells the push plugin which chat you're reading, and what the chats are called.
    func reportFocus() {
        guard isSignedIn else { return }
        let names = Dictionary(contacts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let visible = visibleContactID
        Task { await push.report(visible: visible, names: names) }
    }

    /// Whether you're at the app, on any of its surfaces. The chat on screen doesn't notify while
    /// you are; others still do.
    public var isFocused: Bool { push.isFocused }

    public func setWindowFocused(_ focused: Bool) {
        push.isWindowFocused = focused
        reportFocus()
    }

    /// The quick panel takes the keyboard without making the app active.
    public func setPanelOpen(_ open: Bool) {
        push.isPanelOpen = open
        reportFocus()
    }

    public var isSignedIn: Bool {
        if case .signedIn = session { return true }
        return false
    }

    /// Whether what you type into Settings would cross the network unencrypted.
    public var gatewayIsUnencrypted: Bool { auth?.gateway.isUnencrypted ?? false }

    /// Opens the chat a `usualbot://chat/<id>` link names: what a push notification carries. A
    /// `share` link is the share extension's, which left something in the shared folder. It comes
    /// under the build's own scheme as well (`UsualAppScheme`), so a development build's extension
    /// opens that build and not the released app.
    public func open(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "usualbot" || scheme == Self.ownScheme else { return }
        if url.host() == "share" { return lookForSharedItems() }
        guard url.scheme == "usualbot", url.host() == "chat", url.pathComponents.count == 2 else { return }
        requestedContactID = url.pathComponents[1]
    }

    /// The link scheme only this build answers to: its bundle identifier.
    static var ownScheme: String? { Bundle.main.bundleIdentifier?.lowercased() }

    /// Whether a chat or room is mid-reply, so closing the link now would lose the end of it.
    public var isWorking: Bool {
        threads.values.contains { $0.state.isRunning } || rooms.values.contains(where: \.isBusy)
    }

    /// Returns when nothing is mid-reply, or `limit` runs out.
    public func finishWork(within limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while isWorking, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Connects for a moment while in the background, so what arrived since the app was last
    /// connected raises alerts. iOS may have launched the app just for this.
    public func checkIn(within limit: Duration = .seconds(20)) async {
        await restore()
        guard let auth, !isForeground else { return }
        isCheckingIn = true
        let traced = Trace.begin("push.checkin")
        defer {
            isCheckingIn = false
            traced.end("online=\(link.isOnline) attached=\(allChatsAttached)")
        }
        connect(auth)
        let start = rosterReads
        let deadline = ContinuousClock.now + limit
        // Two reads, as rooms catch up after the first.
        while rosterReads < start + 2 || !allChatsAttached, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !isForeground else { return }
        saveCache(for: auth.gateway)
        linkTask?.cancel()
        linkTask = nil
    }

    /// A notification says `chat` has something new: connects from the background and loads that
    /// chat first, so tapping the notification opens it with the message there. Returns once it's
    /// loaded, or `limit` runs out, and leaves the link up for that tap; `endWarmUp()` closes it.
    /// Only for the gateway in use: switching gateways waits for the tap.
    public func warmUp(_ chat: Contact.ID, on gateway: String?, within limit: Duration) async {
        await restore()
        guard let auth, !isForeground, gateway == nil || gateway == activeGateway?.id else { return }
        isCheckingIn = true
        let traced = Trace.begin("push.warmup", "chat=\(Trace.tag(chat)) reused=\(linkTask != nil)")
        defer { traced.end("loaded=\(hasLoaded(chat, since: 0)) foreground=\(isForeground)") }
        // Woken again while the last one is still up: that link carries this one too.
        if linkTask == nil { connect(auth) }
        let start = rosterReads
        let deadline = ContinuousClock.now + limit
        while !hasLoaded(chat, since: start), ContinuousClock.now < deadline, !isForeground, !Task.isCancelled {
            // Ahead of the others `attachChats()` opens a few at a time.
            if let contact = contacts.first(where: { $0.id == chat }), contact.kind == .agent {
                openThread(for: contact)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if !isForeground { saveCache(for: auth.gateway) }
    }

    /// Closes the link `warmUp` left up, unless you came to the app meanwhile. Answers whether it did.
    @discardableResult public func endWarmUp() -> Bool {
        guard isCheckingIn, !isForeground, let auth else { return false }
        isCheckingIn = false
        saveCache(for: auth.gateway)
        linkTask?.cancel()
        linkTask = nil
        return true
    }

    /// A Bot Chat once it's attached, which loads its history; a room once the roster has been read
    /// twice since `reads`, as rooms catch up after the first.
    private func hasLoaded(_ chat: Contact.ID, since reads: Int) -> Bool {
        if contacts.first(where: { $0.id == chat })?.kind == .agent { return threads[chat]?.isAttached == true }
        return rosterReads >= reads + 2
    }

    private var allChatsAttached: Bool {
        contacts.allSatisfy { contact in
            contact.kind != .agent || contact.chatID == nil || threads[contact.id]?.isAttached == true
        }
    }
}
