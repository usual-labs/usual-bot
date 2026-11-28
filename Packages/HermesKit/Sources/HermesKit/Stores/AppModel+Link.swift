import Foundation

/// What a chat says under its name about the link, while there's something to say.
public enum LinkNote: Equatable, Sendable {
    /// The device has no route to any network.
    case noNetwork
    /// The socket is down and coming back.
    case connecting
    /// The link is back, and the chat is taking in what it missed.
    case updating

    public var text: String {
        switch self {
        case .noNetwork: String(localized: "No network")
        case .connecting: String(localized: "Connecting…")
        case .updating: String(localized: "Updating…")
        }
    }
}

/// How the link stands, for the chat name's second line, the strip above the message box and the
/// chat list's pill.
public struct LinkStatus: Equatable, Sendable {
    /// Signed in to a real gateway: the demo and the connect screen say nothing.
    public var applies: Bool
    public var hasNetwork: Bool
    public var isOnline: Bool
    /// When the link last stopped being online.
    public var offlineSince: Date?

    public init(applies: Bool, hasNetwork: Bool, isOnline: Bool, offlineSince: Date?) {
        self.applies = applies
        self.hasNetwork = hasNetwork
        self.isOnline = isOnline
        self.offlineSince = offlineSince
    }

    /// Nothing to say: online, or no gateway.
    public static let quiet = LinkStatus(applies: false, hasNetwork: true, isOnline: true, offlineSince: nil)

    /// What a chat or room says under its name. `catchingUp` is a chat that isn't attached yet on
    /// a link that's up; a room has no such state.
    public func note(catchingUp: Bool = false) -> LinkNote? {
        guard applies else { return nil }
        if !hasNetwork { return .noNetwork }
        guard isOnline else { return .connecting }
        return catchingUp ? .updating : nil
    }
}

/// Keeping the link light and quick to come back on a bad network: when the roster is read, and
/// what the device's own network says.
extension AppModel {
    public var linkStatus: LinkStatus {
        LinkStatus(
            applies: isSignedIn && (!isDemo || showsDemoLink), hasNetwork: hasNetwork, isOnline: link.isOnline,
            offlineSince: offlineSince)
    }

    #if DEBUG
        /// The demo with its link down (`--demo-link-down`, `--demo-no-network`), to see what a bad
        /// network shows without one.
        public func showDemoLinkDown(hasNetwork: Bool) {
            showsDemoLink = true
            link = .offline(GatewayError.timedOut.localizedDescription)
            offlineSince = .now.addingTimeInterval(-60)
            self.hasNetwork = hasNetwork
        }
    #endif

    /// Starts following the device's network: a route back, or a move to another network, tries
    /// the gateway at once rather than at the next backoff.
    public func watchNetwork() {
        // The demo never connects, and its network is the one `showDemoLinkDown` says.
        guard networkWatcher == nil, !isDemo else { return }
        networkWatcher = NetworkWatcher { [weak self] in self?.networkChanged($0) }
    }

    func networkChanged(_ path: NetworkPath) {
        let hadNetwork = hasNetwork
        let moved = networkRoute != nil && networkRoute != path.route
        hasNetwork = path.isSatisfied
        networkRoute = path.route
        guard path.isSatisfied, let auth, linkTask != nil else { return }
        if link.isOnline {
            // The socket may have gone with the old network, and would take 45 s of silence to say so.
            if moved, let channel { Task { await channel.probe() } }
        } else if !hadNetwork || moved {
            Trace.event("link.network", "moved=\(moved)")
            connect(auth)
        }
    }

    /// Rooms learn of new messages only from the roster read (`refreshRooms`), so it comes often
    /// while one is on screen or at work.
    var rosterWatchesRooms: Bool {
        rooms.contains { id, room in isShown(id) || room.activity != .idle || room.phase != .ready }
    }

    /// Waits until the roster is due again: `rosterInterval`, or `busyRosterInterval` while rooms or
    /// a notification's check-in need it. `readRosterSoon()` cuts the wait short, though never to
    /// less than `busyRosterInterval` after the last read.
    func waitForRosterRead() async throws {
        let interval = rosterWatchesRooms || isCheckingIn ? Self.busyRosterInterval : Self.rosterInterval
        let wait = Task<Void, Never> { try? await Task.sleep(for: interval) }
        rosterWait = wait
        await withTaskCancellationHandler {
            await wait.value
        } onCancel: {
            wait.cancel()
        }
        rosterWait = nil
        try Task.checkCancellation()
        if let last = lastRosterRead, ContinuousClock.now - last < Self.busyRosterInterval {
            try await Task.sleep(for: Self.busyRosterInterval - (ContinuousClock.now - last))
        }
    }

    /// Brings the next roster read forward, e.g. when a chat changed elsewhere.
    func readRosterSoon() {
        rosterWait?.cancel()
    }
}
