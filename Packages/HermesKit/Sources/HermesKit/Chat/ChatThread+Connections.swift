import Foundation

/// A connection request on screen, and what this device is doing about it.
public struct ConnectionCard: Equatable, Sendable {
    public internal(set) var request: ConnectionRequest
    /// Apps whose sign-in page was opened here: their card waits for you to finish there.
    public internal(set) var opened: Set<String> = []
    /// Apps with an answer on its way to the gateway.
    public internal(set) var busy: Set<String> = []
    /// Why the last answer didn't go through.
    public internal(set) var problem: String?
}

extension ChatThread {
    /// `connection.request` opens a card, `connection.update` moves it. Both carry every app.
    func applyConnection(_ event: GatewayEvent) {
        guard let sessionID = event.sessionID ?? self.sessionID else { return }
        if event.type == "connection.request", connection?.request.id != event.payload["op_id"]?.stringValue {
            guard let request = ConnectionRequest(event.payload, sessionID: sessionID) else { return }
            show(request)
            return
        }
        guard var card = connection, card.request.apply(event.payload) else { return }
        connection = card
        if card.request.isSettled { end() }
    }

    /// Takes the request Hermes still waits on when the chat attaches. One shown here that Hermes
    /// no longer has ended while this device was away, and how it ended isn't known.
    func adoptConnection(_ pending: JSONValue?) {
        if let pending, let sessionID, let request = ConnectionRequest(pending: pending, sessionID: sessionID),
            !request.isSettled
        {
            show(request)
            return
        }
        guard let card = connection else { return }
        connection = nil
        let names = card.request.open.map(\.title).formatted(.list(type: .and))
        if !names.isEmpty {
            state.addNotice(String(localized: "The request to connect \(names) ended while this device was away."))
        }
    }

    private func show(_ request: ConnectionRequest) {
        var card = ConnectionCard(request: request)
        if let shown = connection, shown.request.id == request.id {
            // The same request again (a reattach): keep what this device knows about it.
            card.opened = shown.opened
            if shown.request.seq > request.seq { card.request = shown.request }
        }
        connection = card
        if card.request.isSettled { end() }
    }

    /// The request is over: the card goes, and the chat says how it ended.
    private func end() {
        guard let card = connection else { return }
        connection = nil
        for line in card.request.endNotices { state.addNotice(line) }
        announceRequests()
    }

    // MARK: - Your answers

    /// Connect: returns the sign-in page to open, or tells Hermes to go ahead with an MCP install or
    /// switch-on and returns `nil`.
    public func connect(_ target: ConnectionRequest.Target) -> URL? {
        guard var card = connection, card.request.targets.contains(where: { $0.name == target.name }) else {
            return nil
        }
        switch target.offer {
        case .signIn(let url):
            card.opened.insert(target.name)
            card.problem = nil
            connection = card
            #if DEBUG
                if playsDemoReplies {
                    demoConnect(target.name)
                    return nil
                }
            #endif
            return url
        case .approve:
            sendConnectionAnswer(target.name, ConnectionRequest.approveAnswer(target.name))
        default:
            break
        }
        return nil
    }

    /// Try Again after a failure or an expired link. A hosted app gets a fresh link from
    /// `connectors.connect`; an MCP server runs again through `connection.respond`.
    public func retry(_ target: ConnectionRequest.Target) {
        guard target.offer == .retry, var card = connection else { return }
        card.opened.remove(target.name)
        connection = card
        guard target.kind == .connector else {
            sendConnectionAnswer(target.name, ConnectionRequest.approveAnswer(target.name))
            return
        }
        guard let channel = channel() else { return }
        let request = card.request
        setBusy(target.name, true)
        Task {
            do {
                let snapshot = try await channel.call(
                    "connectors.connect", params: request.retryParams(target.name), timeout: .seconds(45))
                guard var card = connection, card.request.id == request.id else { return }
                card.request.apply(snapshot)
                card.problem = nil
                connection = card
            } catch {
                failed(error, request: request)
            }
            setBusy(target.name, false)
        }
    }

    /// Not now, for every app still waiting. Hermes tells the agent you skipped them.
    public func skipConnection() {
        guard let card = connection, !card.request.open.isEmpty else { return }
        #if DEBUG
            if playsDemoReplies {
                demoSettle { $0.state = $0.isResolved ? $0.state : .skipped }
                return
            }
        #endif
        sendConnectionAnswer(nil, card.request.skipAnswer)
    }

    /// Done, on a list of apps: the agent goes on with whatever you connected.
    public func finishConnecting() {
        guard connection != nil else { return }
        #if DEBUG
            if playsDemoReplies {
                connection = nil
                return
            }
        #endif
        sendConnectionAnswer(nil, ConnectionRequest.continueAnswer)
    }

    /// Sends one answer. The card moves when Hermes's next frame says so, not before.
    private func sendConnectionAnswer(_ name: String?, _ result: JSONValue) {
        guard let card = connection, let channel = channel() else { return }
        let request = card.request
        let names = name.map { [$0] } ?? request.open.map(\.name)
        for name in names { setBusy(name, true) }
        Task {
            do {
                let reply = try await channel.call("connection.respond", params: request.respond(result))
                if reply["settled"]?.boolValue == true, connection?.request.id == request.id,
                    var card = connection, !card.request.isSettled
                {
                    // The frame saying so may come after the answer.
                    card.request.ending = result == ConnectionRequest.continueAnswer ? .continued : .allResolved
                    if result == request.skipAnswer {
                        for index in card.request.targets.indices where !card.request.targets[index].isResolved {
                            card.request.targets[index].state = .skipped
                        }
                    }
                    connection = card
                    end()
                }
            } catch {
                failed(error, request: request)
            }
            for name in names { setBusy(name, false) }
        }
    }

    private func setBusy(_ name: String, _ busy: Bool) {
        guard var card = connection else { return }
        if busy { card.busy.insert(name) } else { card.busy.remove(name) }
        connection = card
    }

    private func failed(_ error: any Error, request: ConnectionRequest) {
        guard var card = connection, card.request.id == request.id else { return }
        if case GatewayError.rpc(code: 4004, _) = error {
            // Hermes already let go of it: answered on another device, or over.
            connection = nil
            let names = request.open.map(\.title).formatted(.list(type: .and))
            if !names.isEmpty {
                state.addNotice(String(localized: "The request to connect \(names) had already ended."))
            }
            announceRequests()
            return
        }
        card.problem = ConnectorErrors.describe(error)
        connection = card
    }

    #if DEBUG
        /// The demo: a sign-in "finishes" a moment later, as there's no gateway to report it.
        private func demoConnect(_ name: String) {
            Task {
                try? await Task.sleep(for: .seconds(2))
                demoSettle { if $0.name == name { $0.state = .connected } }
            }
        }

        private func demoSettle(_ change: (inout ConnectionRequest.Target) -> Void) {
            guard var card = connection else { return }
            for index in card.request.targets.indices { change(&card.request.targets[index]) }
            card.request.seq += 1
            if card.request.targets.allSatisfy(\.isResolved) { card.request.ending = .allResolved }
            connection = card
            if card.request.isSettled { end() }
        }

        /// Previews and the demo: a request waiting in this chat.
        func showDemo(_ request: ConnectionRequest) { connection = ConnectionCard(request: request) }
    #endif
}

extension ConnectionRequest {
    /// A `pending_connection` snapshot, which Hermes sends only while the request is open.
    init?(pending: JSONValue, sessionID: String) {
        guard case .object = pending else { return nil }
        self.init(pending, sessionID: sessionID)
    }
}

/// Plain words for what the connector methods refuse with.
@MainActor
enum ConnectorErrors {
    static func describe(_ error: any Error) -> String {
        guard case GatewayError.rpc(let code, _) = error else { return AppModel.describe(error) }
        switch code {
        case 4031:
            return String(
                localized: "This gateway doesn't offer connected apps. They come with a Nous Portal account in Hermes.")
        case 4032: return String(localized: "Sign in to the Nous Portal in the Hermes app first, then try again.")
        case 4030: return String(localized: "Your Nous Portal account isn't allowed to manage connected apps.")
        case 4002: return String(localized: "Hermes can't do that for this app right now.")
        case 5033: return String(localized: "This chat runs on another computer, so its apps are managed there.")
        default: return AppModel.describe(error)
        }
    }
}
