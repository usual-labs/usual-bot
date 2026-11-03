import Foundation
import Observation

/// One agent's MCP servers, from the dashboard's MCP routes: listed, switched, added, tested,
/// signed in and removed there. Every call names the profile. What you type for a server (a token,
/// an API key) goes to the gateway in the request and isn't kept here.
@MainActor
@Observable
public final class MCPServerList {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// The last connection test of a server.
    public enum Check: Equatable {
        case running
        case passed([MCPTool])
        /// What went wrong, as a sentence to show.
        case failed(String)
    }

    /// A sign-in under way, or the reason the last one didn't finish.
    public enum SignIn: Equatable {
        case starting
        /// The provider's page is open in the browser.
        case waiting
        case failed(String)
    }

    /// The Hermes profile the servers belong to.
    public let profile: String
    public private(set) var servers: [MCPServer] = []
    public private(set) var phase: Phase = .loading
    public internal(set) var catalog: [MCPCatalogEntry] = []
    public internal(set) var catalogPhase: Phase = .loading
    public internal(set) var checks: [MCPServer.ID: Check] = [:]
    public internal(set) var signIns: [MCPServer.ID: SignIn] = [:]
    /// Something changed that running chats don't have yet.
    public internal(set) var needsApply = false
    /// What just happened, when it's worth saying.
    public internal(set) var notice: String?
    /// The last action that didn't go through, with anything you typed taken out.
    public internal(set) var problem: String?

    let auth: @MainActor () -> AuthSession?
    let channel: @MainActor () -> JSONRPCChannel?
    let sessionID: @MainActor () -> String?
    let gatewayIsUnencrypted: @MainActor () -> Bool
    let pollInterval: Duration
    /// Sign-in flows under way, by server.
    var flows: [MCPServer.ID: String] = [:]
    /// The demo applies changes without a gateway.
    var isDemo = false
    private var refreshing = false

    init(
        profile: String, auth: @escaping @MainActor () -> AuthSession?,
        channel: @escaping @MainActor () -> JSONRPCChannel? = { nil },
        sessionID: @escaping @MainActor () -> String? = { nil },
        gatewayIsUnencrypted: @escaping @MainActor () -> Bool = { false }, pollInterval: Duration = .seconds(2)
    ) {
        self.profile = profile
        self.auth = auth
        self.channel = channel
        self.sessionID = sessionID
        self.gatewayIsUnencrypted = gatewayIsUnencrypted
        self.pollInterval = pollInterval
    }

    /// A token or key would cross the network unencrypted, so it needs your say-so each time.
    public var isUnencrypted: Bool { gatewayIsUnencrypted() }

    /// Whether the agent has a chat open that changes can be applied to now.
    public var canApplyNow: Bool { isDemo || (sessionID() != nil && channel() != nil) }

    /// Reloads the list. Keeps showing the old one if the reload fails.
    public func refresh() async {
        guard !refreshing, let auth = auth() else { return }
        refreshing = true
        defer { refreshing = false }
        struct Listing: Decodable, Sendable { let servers: [MCPServer] }
        do {
            servers = try await auth.json(Listing.self, path: path("/api/mcp/servers")).servers
            phase = .ready
        } catch {
            if phase != .ready { phase = .failed(AppModel.describe(error)) }
        }
    }

    /// Turns a server on or off. The switch moves at once and moves back if the gateway refuses.
    public func setEnabled(_ enabled: Bool, for server: MCPServer) async {
        guard !server.isFromPlugin, let index = servers.firstIndex(where: { $0.id == server.id }),
            let auth = auth()
        else { return }
        clearMessages()
        servers[index].enabled = enabled
        struct Toggle: Encodable, Sendable {
            let enabled: Bool
            let profile: String
        }
        do {
            _ = try await auth.json(
                Reply.self, path: path("/api/mcp/servers/\(Self.escape(server.name))/enabled"), method: "PUT",
                body: Toggle(enabled: enabled, profile: profile))
            needsApply = true
        } catch {
            if let current = servers.firstIndex(where: { $0.id == server.id }) { servers[current].enabled = !enabled }
            problem =
                enabled
                ? String(localized: "Couldn't turn on “\(server.name)”: \(AppModel.describe(error))")
                : String(localized: "Couldn't turn off “\(server.name)”: \(AppModel.describe(error))")
        }
    }

    /// Adds a server you describe. Returns whether it was added; if not, `problem` says why and
    /// the caller keeps the form. On an unencrypted address a token goes out only with
    /// `allowingUnencrypted`.
    public func add(_ draft: MCPServerDraft, allowingUnencrypted: Bool = false) async -> Bool {
        guard draft.isComplete, allowingUnencrypted || !draft.hasSecret || !isUnencrypted, let auth = auth()
        else { return false }
        clearMessages()
        var body = draft.body
        body.profile = profile
        do {
            _ = try await auth.json(Reply.self, path: path("/api/mcp/servers"), method: "POST", body: body)
            needsApply = true
            await refresh()
            return true
        } catch {
            problem = String(
                localized: "Couldn't add “\(body.name)”: \(Self.describe(error, removing: [draft.token]))")
            return false
        }
    }

    /// Removes a server from the profile for good.
    public func remove(_ server: MCPServer) async -> Bool {
        guard !server.isFromPlugin, let auth = auth() else { return false }
        clearMessages()
        do {
            _ = try await auth.json(
                Reply.self, path: path("/api/mcp/servers/\(Self.escape(server.name))"), method: "DELETE")
            servers.removeAll { $0.id == server.id }
            checks[server.id] = nil
            needsApply = true
            return true
        } catch {
            problem = String(localized: "Couldn't remove “\(server.name)”: \(AppModel.describe(error))")
            return false
        }
    }

    /// Connects to a server on the gateway, lists its tools and disconnects.
    public func test(_ server: MCPServer) async {
        guard let auth = auth() else { return }
        checks[server.id] = .running
        struct Result: Decodable, Sendable {
            let ok: Bool
            let tools: [MCPTool]?
            let error: String?
        }
        do {
            // A program the gateway has to fetch first can take a while to answer.
            let result = try await auth.json(
                Result.self, path: path("/api/mcp/servers/\(Self.escape(server.name))/test"), method: "POST",
                timeout: 120)
            if result.ok {
                checks[server.id] = .passed(result.tools ?? [])
            } else if result.error?.hasPrefix("OAuth authentication required") == true {
                checks[server.id] = .failed(String(localized: "Sign in first, then test again."))
            } else {
                let reason = result.error ?? String(localized: "no reason given")
                checks[server.id] = .failed(String(localized: "It didn't connect: \(reason)"))
            }
        } catch {
            checks[server.id] = .failed(String(localized: "Couldn't test it: \(AppModel.describe(error))"))
        }
    }

    /// Loads Hermes's catalog, marking what's already added.
    public func loadCatalog() async {
        guard let auth = auth() else { return }
        struct Listing: Decodable, Sendable { let entries: [MCPCatalogEntry] }
        do {
            catalog = try await auth.json(Listing.self, path: path("/api/mcp/catalog")).entries
            catalogPhase = .ready
        } catch {
            if catalogPhase != .ready { catalogPhase = .failed(AppModel.describe(error)) }
        }
    }

    /// Adds a catalog server with the values it asks for, switched on. Returns whether the gateway
    /// took it; if not, `problem` says why and the caller keeps the form. On an unencrypted address
    /// the values go out only with `allowingUnencrypted`.
    public func install(
        _ entry: MCPCatalogEntry, values: [String: String], allowingUnencrypted: Bool = false
    ) async -> Bool {
        let env = values.filter { !$0.value.isEmpty }
        guard allowingUnencrypted || env.isEmpty || !isUnencrypted, let auth = auth() else { return false }
        clearMessages()
        struct Install: Encodable, Sendable {
            let name: String
            let env: [String: String]
            let enable: Bool
            let profile: String
        }
        struct Installed: Decodable, Sendable { let background: Bool? }
        do {
            let reply = try await auth.json(
                Installed.self, path: path("/api/mcp/catalog/install"), method: "POST",
                body: Install(name: entry.name, env: env, enable: true, profile: profile), timeout: 120)
            needsApply = true
            if reply.background == true {
                notice = String(localized: "The gateway is fetching “\(entry.name)”. It shows here when it's ready.")
                Task { await waitForInstall(of: entry.name) }
            } else {
                await refresh()
            }
            await loadCatalog()
            return true
        } catch {
            problem = String(
                localized: "Couldn't add “\(entry.name)”: \(Self.describe(error, removing: Array(env.values)))")
            return false
        }
    }

    /// Brings this profile's running chats up to date with its servers, through the agent's open
    /// chat. Hermes reloads the servers and the next reply costs more, since the conversation is
    /// sent again in full.
    public func applyNow() async {
        clearMessages()
        if isDemo {
            needsApply = false
            notice = String(localized: "Applied. The chat uses these apps from its next message.")
            return
        }
        guard let sessionID = sessionID(), let channel = channel() else {
            problem = String(localized: "Open a chat with this Bot first, then apply.")
            return
        }
        do {
            // Never `always`: that would switch off Hermes's own cost warning for good.
            let result = try await channel.call(
                "reload.mcp", params: ["session_id": .string(sessionID), "confirm": true], timeout: .seconds(120))
            guard result["status"]?.stringValue == "reloaded" else {
                problem = result["message"]?.stringValue ?? String(localized: "The gateway didn't apply the changes.")
                return
            }
            needsApply = false
            let missing: [String] = {
                guard case .array(let names) = result["unavailable"] else { return [] }
                return names.compactMap(\.stringValue)
            }()
            notice =
                missing.isEmpty
                ? String(localized: "Applied. The chat uses these apps from its next message.")
                : String(localized: "Applied, but these didn't connect: \(missing.joined(separator: ", ")).")
        } catch {
            problem = String(localized: "Couldn't apply the changes: \(AppModel.describe(error))")
        }
    }

    /// Keeps reloading for a few minutes until a server being fetched appears.
    private func waitForInstall(of name: String) async {
        for _ in 0..<36 {
            try? await Task.sleep(for: pollInterval * 2.5)
            await refresh()
            if servers.contains(where: { $0.name == name }) {
                if notice?.contains(name) == true { notice = nil }
                return
            }
        }
        notice = nil
        problem = String(
            localized: "“\(name)” didn't show up. The gateway may still be fetching it, or it failed there.")
    }

    /// Clears the notice and problem, say when a sheet opens.
    public func clearMessages() {
        problem = nil
        notice = nil
    }

    func path(_ route: String) -> String {
        "\(route)?profile=\(Self.escape(profile))"
    }

    static func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? component
    }

    /// An error in words, with anything typed into the form taken out.
    static func describe(_ error: any Error, removing secrets: [String]) -> String {
        VaultRedaction.scrub(AppModel.describe(error), removing: secrets)
    }

    /// Any JSON object: the routes' `{ok: true}` replies aren't read.
    struct Reply: Decodable, Sendable {}
}
