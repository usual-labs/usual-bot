import Foundation

/// What keeps iPhone notifications going once the app has left the screen.
extension AppModel {
    /// Tells the push plugin whether you're at the app, and what the chats are called.
    func reportFocus() {
        guard push.isActive else { return }
        let names = Dictionary(contacts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        Task { await push.report(names: names) }
    }

    /// Whether you're at the app, on any of its surfaces. Nothing notifies while you are.
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

    /// Opens the chat a `usualbot://chat/<id>` link names: what a push notification carries.
    public func open(_ url: URL) {
        guard url.scheme == "usualbot", url.host() == "chat", url.pathComponents.count == 2 else { return }
        requestedContactID = url.pathComponents[1]
    }

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
        defer { isCheckingIn = false }
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

    private var allChatsAttached: Bool {
        contacts.allSatisfy { contact in
            contact.kind != .agent || contact.chatID == nil || threads[contact.id]?.isAttached == true
        }
    }
}
