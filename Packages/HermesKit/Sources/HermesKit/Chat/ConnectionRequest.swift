import Foundation

/// The agent asked to connect apps (Hermes's `manage_connections`): hosted connectors such as Gmail,
/// which sign in through the Nous Portal, or MCP servers on the gateway. Hermes keeps one of these
/// open per chat and holds the agent's turn until every app is connected or skipped, you continue
/// without the rest, the reply is stopped, or five minutes pass. The card only says skip, approve or
/// try again; whether an app connected is Hermes's to report, in `connection.update`.
public struct ConnectionRequest: Identifiable, Equatable, Sendable {
    public struct Target: Identifiable, Equatable, Sendable {
        public enum Kind: String, Sendable {
            /// A hosted connector account, signed in to on the vendor's page through the Nous Portal.
            case connector
            /// An MCP server on the gateway: installed, turned on or signed in to there.
            case mcp
            /// A catalog plugin or skill (`manage_catalog`), and anything newer: answered in the Hermes app.
            case other
        }

        public enum State: String, Sendable {
            case pending, initiated, connected, skipped, failed, expired
            /// What Hermes stamps on every app left open when the request ends.
            case notConnected = "not_connected"
        }

        /// What you can do about the app here.
        public enum Offer: Equatable, Sendable {
            /// Open its sign-in page.
            case signIn(URL)
            /// Tell Hermes to go ahead (an MCP install or switch-on that needs nothing typed).
            case approve
            /// Start again after a failure or an expired link.
            case retry
            /// Hermes is still getting the sign-in page.
            case preparing
            /// It needs something this app doesn't ask for, such as an API key or a plugin review.
            case elsewhere
            /// Connected, skipped or over.
            case none
        }

        public var id: String { name }
        /// Hermes's slug for the app, e.g. `gmail`, or the MCP server's name.
        public let name: String
        public let kind: Kind
        /// `connect`, `reconnect`, `authorize`, `install` or `enable`.
        public let action: String
        public internal(set) var state: State
        /// The vendor's or the gateway's words about the last attempt, when it said any.
        public internal(set) var detail: String?
        /// Setup notes from the catalog, for an MCP server.
        public internal(set) var instructions: String?
        public internal(set) var connectURL: URL?
        /// An MCP install that still needs credentials typed in.
        public internal(set) var needsCredentials = false
        /// The name to show.
        public let title: String

        init?(_ value: JSONValue) {
            guard let name = value["name"]?.stringValue?.nonBlank else { return nil }
            self.name = name
            kind = Kind(rawValue: value["kind"]?.stringValue ?? "") ?? .other
            action = value["action"]?.stringValue ?? "connect"
            state = State(rawValue: value["state"]?.stringValue ?? "") ?? .pending
            detail = value["detail"]?.stringValue?.nonBlank
            instructions = value["instructions"]?.stringValue?.nonBlank
            connectURL = value["connect_url"]?.stringValue.flatMap(URL.init(string:)).flatMap { url in
                ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? url : nil
            }
            if case .array(let fields) = value["required_env"] { needsCredentials = !fields.isEmpty }
            title = value["display"]?.stringValue?.nonBlank ?? Self.title(for: name)
        }

        init(name: String, kind: Kind, action: String, state: State, connectURL: URL? = nil, detail: String? = nil) {
            self.name = name
            self.kind = kind
            self.action = action
            self.state = state
            self.connectURL = connectURL
            self.detail = detail
            title = Self.title(for: name)
        }

        /// Connected or skipped: nothing more to do.
        public var isResolved: Bool { state == .connected || state == .skipped }

        public var offer: Offer {
            switch state {
            case .connected, .skipped, .notConnected: return .none
            case .failed, .expired: return kind == .other || needsCredentials ? .elsewhere : .retry
            case .pending, .initiated:
                if kind == .other || needsCredentials { return .elsewhere }
                if let connectURL { return .signIn(connectURL) }
                if kind == .mcp, state == .pending, action == "install" || action == "enable" { return .approve }
                return .preparing
            }
        }

        /// `google_drive` → "Google Drive". Hermes's catalog names are slugs.
        static func title(for name: String) -> String {
            name.split(whereSeparator: { $0 == "_" || $0 == "-" })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// Why the request ended (`settled_by`).
    public enum Ending: String, Sendable {
        /// Every app was connected or skipped.
        case allResolved = "all_resolved"
        /// You went on without the rest.
        case continued = "continue"
        /// Five minutes passed.
        case deadline
        /// The reply was stopped.
        case interrupt
    }

    /// Hermes's operation ID (`op_id`).
    public let id: String
    /// The live session it belongs to.
    public let sessionID: String
    /// The newest frame applied. Frames can arrive out of order; an older one changes nothing.
    public internal(set) var seq: Int
    /// When Hermes stops waiting.
    public let deadline: Date
    public internal(set) var targets: [Target]
    /// A list of apps to pick from (`display`), with these suggested. It has no rows of its own:
    /// apps are connected from the agent's Apps page, and Done tells the agent you've finished.
    public let suggested: [String]?
    public internal(set) var ending: Ending?

    public var isSettled: Bool { ending != nil }
    public var isList: Bool { suggested != nil }
    /// The apps still waiting for you.
    public var open: [Target] { targets.filter { !$0.isResolved && $0.state != .notConnected } }

    /// Reads a `connection.request` payload, or the `pending_connection` a chat brings back on attach.
    init?(_ payload: JSONValue, sessionID: String) {
        guard let id = payload["op_id"]?.stringValue?.nonBlank else { return nil }
        self.id = id
        self.sessionID = sessionID
        seq = payload["seq"]?.intValue ?? 0
        if case .number(let seconds) = payload["deadline_at"] {
            deadline = Date(timeIntervalSince1970: seconds)
        } else {
            deadline = .now + 300
        }
        if case .array(let rows) = payload["targets"] { targets = rows.compactMap(Target.init) } else { targets = [] }
        if case .array(let names) = payload["display"]?["suggested"] {
            suggested = names.compactMap(\.stringValue).map(Target.title(for:))
        } else if payload["display"] != nil {
            suggested = []
        } else {
            suggested = nil
        }
        // A request for nothing would have nothing to answer.
        guard !targets.isEmpty || suggested != nil else { return nil }
        ending = Self.ending(payload)
    }

    init(id: String, sessionID: String, targets: [Target], suggested: [String]? = nil, deadline: Date = .now + 300) {
        self.id = id
        self.sessionID = sessionID
        self.targets = targets
        self.suggested = suggested
        self.deadline = deadline
        seq = 0
    }

    /// Applies a `connection.update` frame, or the snapshot `connectors.connect` answers with.
    /// Every frame carries all the apps; one for another request, or older than what's shown, is
    /// ignored. Returns whether anything changed.
    @discardableResult
    mutating func apply(_ payload: JSONValue) -> Bool {
        guard payload["op_id"]?.stringValue == id, let frame = payload["seq"]?.intValue, frame > seq else {
            return false
        }
        seq = frame
        if case .array(let rows) = payload["targets"] {
            let fresh = rows.compactMap(Target.init)
            // An account request's frames leave the link out; keep the one already held.
            targets = fresh.map { target in
                var target = target
                if target.connectURL == nil, target.state == .initiated {
                    target.connectURL = targets.first { $0.name == target.name }?.connectURL
                }
                return target
            }
        }
        ending = Self.ending(payload) ?? ending
        return true
    }

    private static func ending(_ payload: JSONValue) -> Ending? {
        let settled = payload["settled"]?.boolValue == true || payload["settled_at"].map { $0 != .null } == true
        guard settled else { return nil }
        return payload["settled_by"]?.stringValue.flatMap(Ending.init(rawValue:)) ?? .allResolved
    }

    // MARK: - Answers

    /// `connection.respond`'s parameters: the request it answers, and `result`.
    func respond(_ result: JSONValue) -> JSONValue {
        ["owner": ["type": "session", "session_id": .string(sessionID)], "op_id": .string(id), "result": result]
    }

    /// Not now for every app still open.
    var skipAnswer: JSONValue {
        ["targets": .array(open.map { ["name": .string($0.name), "status": "skipped"] })]
    }

    /// Go ahead with one app: an MCP install or switch-on, or running a failed one again.
    static func approveAnswer(_ name: String) -> JSONValue {
        ["targets": .array([["name": .string(name), "status": "approved"]])]
    }

    /// Done, on a list of apps.
    static let continueAnswer: JSONValue = ["settled_by": "continue"]

    /// `connectors.connect` asking Hermes for a fresh link for a hosted app that failed or expired.
    func retryParams(_ name: String) -> JSONValue {
        [
            "owner": ["type": "session", "session_id": .string(sessionID)], "connectors": .array([.string(name)]),
            "reconnect": true,
        ]
    }

    // MARK: - Words

    /// What the chat says once the request is over: one line per outcome.
    var endNotices: [String] {
        if isList {
            return ending == .deadline ? [String(localized: "The list of apps closed after 5 minutes.")] : []
        }
        var lines: [String] = []
        let names = { (states: Set<Target.State>) in
            targets.filter { states.contains($0.state) }.map(\.title).formatted(.list(type: .and))
        }
        let connected = names([.connected])
        if !connected.isEmpty { lines.append(String(localized: "You connected \(connected)")) }
        let skipped = names([.skipped])
        if !skipped.isEmpty { lines.append(String(localized: "You chose Not now for \(skipped)")) }
        let left = names([.notConnected, .pending, .initiated, .failed, .expired])
        if !left.isEmpty {
            switch ending {
            case .deadline: lines.append(String(localized: "Nobody finished connecting \(left) in time."))
            case .interrupt: lines.append(String(localized: "\(left) didn't connect: the reply was stopped."))
            default: lines.append(String(localized: "You went on without \(left)."))
            }
        }
        return lines
    }

    /// What an alert says while the request waits.
    var alertText: String {
        if isList { return String(localized: "Wants you to connect apps") }
        return String(localized: "Wants to connect \(targets.map(\.title).formatted(.list(type: .and)))")
    }
}
