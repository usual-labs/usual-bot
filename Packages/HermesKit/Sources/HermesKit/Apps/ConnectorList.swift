import Foundation
import Observation

/// The apps an agent can connect through the Nous Portal (Hermes's hosted connectors, such as
/// Gmail or Slack), apart from its MCP servers. The accounts belong to the Nous Portal sign-in of the
/// agent's profile, and the agent uses them through Hermes's own tools. Everything goes through
/// the dashboard socket's `connectors.*` methods with an account owner.
@MainActor
@Observable
public final class ConnectorList {
    public enum Phase: Equatable {
        case loading
        case ready
        /// This gateway or profile has no hosted connectors (no Nous Portal account).
        case unavailable
        case failed(String)
    }

    public struct Connector: Identifiable, Equatable, Sendable {
        public var id: String { slug }
        public let slug: String
        public let name: String
        public let summary: String?
        public internal(set) var isConnected: Bool
        /// The vendor's words when the account needs attention.
        public internal(set) var statusReason: String?
        /// Its accounts' IDs, which Disconnect removes. Retired ones are left alone.
        public internal(set) var accountIDs: [String] = []
    }

    /// A connect under way, or why the last one didn't finish.
    public enum Connecting: Equatable, Sendable {
        case starting
        /// The vendor's page is open; Hermes reports when you're done.
        case waiting
        case failed(String)
    }

    public let profile: String
    public private(set) var phase: Phase = .loading
    public private(set) var connectors: [Connector] = []
    public internal(set) var connecting: [Connector.ID: Connecting] = [:]
    public internal(set) var disconnecting: Set<Connector.ID> = []
    /// What just happened, when it's worth saying.
    public internal(set) var notice: String?
    public internal(set) var problem: String?

    let channel: @MainActor () -> JSONRPCChannel?
    let pollInterval: Duration
    /// Connects under way, by app: Hermes's operation for each.
    private var operations: [Connector.ID: String] = [:]
    private var refreshing = false
    /// The demo connects without a gateway.
    var isDemo = false

    init(profile: String, channel: @escaping @MainActor () -> JSONRPCChannel?, pollInterval: Duration = .seconds(2)) {
        self.profile = profile
        self.channel = channel
        self.pollInterval = pollInterval
    }

    private var owner: JSONValue { ["type": "account"] }

    /// Reloads the apps and which are connected. Keeps the old list if the reload fails.
    public func refresh() async {
        guard !isDemo, !refreshing, let channel = channel() else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let listed = try await channel.call(
                "connectors.list", params: ["owner": owner, "profile": .string(profile)], timeout: .seconds(45))
            guard listed["available"]?.boolValue == true else {
                connectors = []
                phase = .unavailable
                return
            }
            async let catalog = try? channel.call("connectors.catalog", params: ["profile": .string(profile)])
            async let accounts = try? channel.call("connectors.accounts", params: ["profile": .string(profile)])
            connectors = Self.merge(listed: listed, catalog: await catalog, accounts: await accounts)
            phase = .ready
        } catch GatewayError.rpc(code: 4031, _) {
            connectors = []
            phase = .unavailable
        } catch {
            if phase != .ready { phase = .failed(ConnectorErrors.describe(error)) }
        }
    }

    /// The catalog names every app on offer; the list says which are connected. Connected first.
    static func merge(listed: JSONValue, catalog: JSONValue?, accounts: JSONValue?) -> [Connector] {
        var rows: [String: (connected: Bool, reason: String?)] = [:]
        if case .array(let items) = listed["connectors"] {
            for item in items {
                guard let slug = item["connector"]?.stringValue?.lowercased(), item["enabled"]?.boolValue != false
                else { continue }
                rows[slug] = (item["connected"]?.boolValue == true, item["status_reason"]?.stringValue?.nonBlank)
            }
        }
        var ids: [String: [String]] = [:]
        if case .array(let items) = accounts?["accounts"] {
            for item in items where item["disabled"]?.boolValue != true {
                guard let slug = item["connector"]?.stringValue?.lowercased(),
                    let id = item["connection_id"]?.stringValue
                else { continue }
                ids[slug, default: []].append(id)
            }
        }
        var entries: [(slug: String, name: String, summary: String?)] = []
        if case .array(let items) = catalog?["connectors"] {
            entries = items.compactMap { item in
                guard let slug = item["slug"]?.stringValue?.lowercased() else { return nil }
                return (
                    slug, item["name"]?.stringValue?.nonBlank ?? ConnectionRequest.Target.title(for: slug),
                    item["description"]?.stringValue?.nonBlank
                )
            }
        }
        for slug in rows.keys where !entries.contains(where: { $0.slug == slug }) {
            entries.append((slug, ConnectionRequest.Target.title(for: slug), nil))
        }
        let connectors = entries.map { entry in
            Connector(
                slug: entry.slug, name: entry.name, summary: entry.summary,
                isConnected: rows[entry.slug]?.connected ?? false, statusReason: rows[entry.slug]?.reason,
                accountIDs: ids[entry.slug] ?? [])
        }
        return connectors.sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
    }

    /// Starts connecting `connector`, opens the vendor's page with `open`, and waits until Hermes
    /// says it's connected, the attempt fails or five minutes pass.
    public func connect(_ connector: Connector, open: @escaping @MainActor (URL) -> Void) async {
        switch connecting[connector.id] {
        case .starting, .waiting: return
        case .failed, nil: break
        }
        notice = nil
        problem = nil
        connecting[connector.id] = .starting
        if isDemo {
            connecting[connector.id] = .waiting
            try? await Task.sleep(for: .seconds(2))
            finish(connector, as: .connected)
            return
        }
        guard let channel = channel() else { return }
        do {
            let started = try await channel.call(
                "connectors.connect",
                params: ["owner": owner, "profile": .string(profile), "connectors": .array([.string(connector.slug)])],
                timeout: .seconds(45))
            guard let id = started["op_id"]?.stringValue else { throw GatewayError.invalidResponse }
            operations[connector.id] = id
            if try await settle(connector, started, open: open) { return }
            await wait(for: connector, operation: id, channel: channel, open: open)
        } catch {
            connecting[connector.id] = .failed(ConnectorErrors.describe(error))
        }
    }

    /// Reads the app's row in an operation snapshot. Returns whether the connect is over; opens the
    /// page the first time one comes.
    private func settle(_ connector: Connector, _ snapshot: JSONValue, open: (@MainActor (URL) -> Void)? = nil)
        async throws -> Bool
    {
        guard case .array(let rows) = snapshot["targets"],
            let target = rows.compactMap(ConnectionRequest.Target.init).first(where: { $0.name == connector.slug })
        else { throw GatewayError.invalidResponse }
        switch target.state {
        case .connected:
            finish(connector, as: .connected)
            return true
        case .failed, .expired, .skipped, .notConnected:
            finish(connector, as: target.state, detail: target.detail)
            return true
        case .pending, .initiated:
            if snapshot["settled"]?.boolValue == true {
                finish(connector, as: .notConnected)
                return true
            }
            if let url = target.connectURL, connecting[connector.id] == .starting {
                connecting[connector.id] = .waiting
                open?(url)
            }
            return false
        }
    }

    private func wait(
        for connector: Connector, operation: String, channel: JSONRPCChannel, open: @escaping @MainActor (URL) -> Void
    ) async {
        let params: JSONValue = ["owner": owner, "profile": .string(profile), "op_id": .string(operation)]
        let deadline = ContinuousClock.now + .seconds(6 * 60)
        var first = true
        while operations[connector.id] == operation, ContinuousClock.now < deadline {
            if !first { try? await Task.sleep(for: pollInterval) }
            first = false
            guard operations[connector.id] == operation else { return }
            do {
                let snapshot = try await channel.call("connectors.operation.status", params: params)
                if try await settle(connector, snapshot, open: open) { return }
            } catch GatewayError.rpc(code: 4004, _) {
                // Hermes let go of it; the list says how it ended.
                operations[connector.id] = nil
                connecting[connector.id] = nil
                await refresh()
                return
            } catch {
                continue
            }
        }
        if operations[connector.id] == operation { finish(connector, as: .expired) }
    }

    private func finish(_ connector: Connector, as state: ConnectionRequest.Target.State, detail: String? = nil) {
        operations[connector.id] = nil
        switch state {
        case .connected:
            connecting[connector.id] = nil
            if let index = connectors.firstIndex(where: { $0.id == connector.id }) {
                connectors[index].isConnected = true
                connectors[index].statusReason = nil
            }
            notice = String(localized: "Connected \(connector.name).")
            if !isDemo { Task { await refresh() } }
        case .skipped:
            connecting[connector.id] = nil
        case .expired, .notConnected:
            connecting[connector.id] = .failed(String(localized: "The sign-in wasn't finished in time. Try again."))
        default:
            connecting[connector.id] = .failed(detail ?? String(localized: "The sign-in didn't finish. Try again."))
        }
    }

    /// Stops waiting for a connect here and on the gateway.
    public func cancelConnecting(_ connector: Connector) async {
        connecting[connector.id] = nil
        guard let operation = operations.removeValue(forKey: connector.id), let channel = channel() else { return }
        let answer: JSONValue = ["targets": .array([["name": .string(connector.slug), "status": "skipped"]])]
        _ = try? await channel.call(
            "connection.respond",
            params: ["owner": owner, "profile": .string(profile), "op_id": .string(operation), "result": answer])
    }

    /// Removes every account of `connector` from the Nous Portal. The agent loses it everywhere.
    public func disconnect(_ connector: Connector) async {
        notice = nil
        problem = nil
        disconnecting.insert(connector.id)
        defer { disconnecting.remove(connector.id) }
        if !isDemo {
            guard let channel = channel() else { return }
            if connector.accountIDs.isEmpty {
                problem = String(localized: "Couldn't find the \(connector.name) account to remove. Try again.")
                await refresh()
                return
            }
            do {
                for id in connector.accountIDs {
                    _ = try await channel.call(
                        "connectors.accounts.remove",
                        params: ["profile": .string(profile), "connection_id": .string(id)])
                }
            } catch {
                problem = String(
                    localized: "Couldn't disconnect \(connector.name): \(ConnectorErrors.describe(error))")
                await refresh()
                return
            }
        }
        if let index = connectors.firstIndex(where: { $0.id == connector.id }) {
            connectors[index].isConnected = false
            connectors[index].accountIDs = []
        }
        notice = String(localized: "Disconnected \(connector.name).")
        if !isDemo { await refresh() }
    }

    #if DEBUG
        /// The demo's apps.
        func showDemo(_ connectors: [Connector]) {
            isDemo = true
            self.connectors = connectors
            phase = .ready
        }
    #endif
}
