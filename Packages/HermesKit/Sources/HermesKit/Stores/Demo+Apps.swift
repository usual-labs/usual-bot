#if DEBUG
    import Foundation
    import Synchronization

    extension MCPServerList {
        /// The demo's apps for one agent: answered in memory by `DemoAppsGateway`, so the real list
        /// code runs and nothing reaches a network. Sign-in finishes on its own without a page.
        static func demo(gateway: GatewayAddress) -> MCPServerList {
            let session = AuthSession(
                gateway: gateway,
                tokens: TokenSet(
                    accessToken: "demo", refreshToken: "demo", expiresAt: .distantFuture, provider: "demo",
                    userID: "demo"),
                store: DemoTokenStore(), http: DemoAppsGateway())
            let list = MCPServerList(profile: "demo", auth: { session }, pollInterval: .milliseconds(900))
            list.isDemo = true
            return list
        }
    }

    /// The demo's connected apps: a Connect card in Atlas's chat and the Apps page's hosted apps.
    /// Its links go nowhere; the demo connects without opening them.
    enum DemoConnections {
        static let request = ConnectionRequest(
            id: "demo-connect", sessionID: "sample",
            targets: [
                .init(
                    name: "notion", kind: .connector, action: "connect", state: .initiated,
                    connectURL: URL(string: "https://hermes.example.com/connect/notion")),
                .init(
                    name: "google_drive", kind: .connector, action: "connect", state: .initiated,
                    connectURL: URL(string: "https://hermes.example.com/connect/google-drive")),
            ])

        static let connectors = [
            ConnectorList.Connector(
                slug: "github", name: "GitHub", summary: "Issues, pull requests and code", isConnected: true),
            ConnectorList.Connector(
                slug: "google_drive", name: "Google Drive", summary: "Docs, sheets and files", isConnected: false),
            ConnectorList.Connector(slug: "gmail", name: "Gmail", summary: "Read and send email", isConnected: false),
            ConnectorList.Connector(
                slug: "notion", name: "Notion", summary: "Pages and databases", isConnected: false),
            ConnectorList.Connector(
                slug: "slack", name: "Slack", summary: "Channels and messages", isConnected: false,
                statusReason: "The Slack token was revoked. Connect again."),
        ]
    }

    private struct DemoTokenStore: TokenStore {
        func load(for gateway: GatewayAddress) throws -> TokenSet? { nil }
        func save(_ tokens: TokenSet, for gateway: GatewayAddress) throws {}
        func delete(for gateway: GatewayAddress) throws {}
    }

    /// Answers the dashboard's MCP routes from memory, the way Hermes shapes them.
    private final class DemoAppsGateway: HTTPTransport {
        private struct State {
            var servers: [String: JSONValue] = DemoAppsGateway.servers
            var signedIn = false
            var polls = 0
        }

        private let state = Mutex(State())

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url ?? URL(fileURLWithPath: "/")
            let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
            let body = request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? [:]
            let (status, reply) = try await answer(request.httpMethod ?? "GET", Array(parts.dropFirst(2)), body)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (try JSONEncoder().encode(reply), response)
        }

        private func answer(_ method: String, _ route: [String], _ body: JSONValue) async throws -> (Int, JSONValue) {
            switch (method, route.first, route.count) {
            case ("GET", "servers", 1):
                let rows = state.withLock { $0.servers.sorted { $0.key < $1.key }.map(\.value) }
                return (200, ["servers": .array(rows)])
            case ("POST", "servers", 1):
                return add(body)
            case ("DELETE", "servers", 2):
                return change(route[1]) { servers in servers[route[1]] = nil }
            case ("PUT", "servers", 3):
                let enabled = body["enabled"]?.boolValue ?? true
                return change(route[1]) { servers in servers[route[1]] = Self.with(servers[route[1]], enabled) }
            case ("POST", "servers", 3) where route[2] == "test":
                // sleep-ok: a short pause so the demo shows the test running.
                try await Task.sleep(for: .milliseconds(700))
                return (200, test(route[1]))
            case ("POST", "servers", 3) where route[2] == "auth":
                state.withLock { $0.polls = 0 }
                return (200, ["flow_id": "demo-flow", "status": "starting", "authorization_url": .null])
            case ("GET", "oauth", _):
                return (200, poll())
            case ("DELETE", "oauth", _):
                return (200, ["ok": true])
            case ("GET", "catalog", 1):
                let installed = state.withLock { Set($0.servers.keys) }
                let rows = Self.catalog.map { entry -> JSONValue in
                    guard case .object(var row) = entry, let name = row["name"]?.stringValue else { return entry }
                    row["installed"] = .bool(installed.contains(name))
                    return .object(row)
                }
                return (200, ["entries": .array(rows)])
            case ("POST", "catalog", 2):
                return install(body)
            default:
                return (404, ["detail": "Not found"])
            }
        }

        private func add(_ body: JSONValue) -> (Int, JSONValue) {
            let name = body["name"]?.stringValue ?? ""
            return state.withLock { state in
                if state.servers[name] != nil { return (409, ["detail": .string("Server '\(name)' already exists")]) }
                state.servers[name] = Self.server(
                    name, url: body["url"]?.stringValue, command: body["command"]?.stringValue,
                    args: body["args"] ?? [],
                    auth: body["auth"]?.stringValue == "none" ? nil : body["auth"]?.stringValue)
                return (200, ["ok": true])
            }
        }

        private func install(_ body: JSONValue) -> (Int, JSONValue) {
            let name = body["name"]?.stringValue ?? ""
            guard let entry = Self.catalog.first(where: { $0["name"]?.stringValue == name }) else {
                return (404, ["detail": .string("No catalog entry '\(name)'")])
            }
            let keys: [JSONValue] = {
                guard case .array(let keys) = entry["required_env"] else { return [] }
                return keys
            }()
            let env = Dictionary(uniqueKeysWithValues: keys.compactMap(\.["name"]?.stringValue).map { ($0, "***") })
            return state.withLock { state in
                state.servers[name] = Self.server(
                    name, url: entry["url"]?.stringValue, command: entry["command"]?.stringValue,
                    args: entry["args"] ?? [], env: env,
                    auth: entry["auth_type"]?.stringValue == "oauth" ? "oauth" : nil)
                return (200, ["ok": true, "name": .string(name), "background": false])
            }
        }

        private func change(_ name: String, _ edit: (inout [String: JSONValue]) -> Void) -> (Int, JSONValue) {
            state.withLock { state in
                guard let server = state.servers[name] else {
                    return (404, ["detail": .string("Server '\(name)' not found")])
                }
                if let plugin = server["plugin"]?.stringValue {
                    return (
                        409,
                        ["detail": .string("Server '\(name)' is provided by plugin '\(plugin)' and cannot be modified")]
                    )
                }
                edit(&state.servers)
                return (200, ["ok": true])
            }
        }

        private func test(_ name: String) -> JSONValue {
            let (server, signedIn) = state.withLock { ($0.servers[name], $0.signedIn) }
            if server?["auth"]?.stringValue == "oauth" && !signedIn {
                return ["ok": false, "error": "OAuth authentication required — no token found.", "tools": []]
            }
            return ["ok": true, "tools": .array(Self.tools(for: name))]
        }

        private func poll() -> JSONValue {
            state.withLock { state in
                state.polls += 1
                guard state.polls > 2 else {
                    return ["flow_id": "demo-flow", "status": "authorization_required", "authorization_url": .null]
                }
                state.signedIn = true
                return ["flow_id": "demo-flow", "status": "approved", "tools": .array(Self.tools(for: "linear"))]
            }
        }

        private static func with(_ server: JSONValue?, _ enabled: Bool) -> JSONValue? {
            guard case .object(var row) = server else { return server }
            row["enabled"] = .bool(enabled)
            return .object(row)
        }

        private static func server(
            _ name: String, url: String? = nil, command: String? = nil, args: JSONValue = [],
            env: [String: String] = [:], auth: String? = nil, enabled: Bool = true, plugin: String? = nil
        ) -> JSONValue {
            [
                "name": .string(name), "transport": url != nil ? "http" : "stdio",
                "url": url.map { .string($0) } ?? .null,
                "command": command.map { .string($0) } ?? .null, "args": args,
                "env": .object(env.mapValues { .string($0) }), "auth": auth.map { .string($0) } ?? .null,
                "enabled": .bool(enabled), "tools": .null, "source": plugin == nil ? "config" : "plugin",
                "plugin": plugin.map { .string($0) } ?? .null,
            ]
        }

        private static let servers: [String: JSONValue] = [
            "github": server(
                "github", command: "npx", args: ["-y", "@modelcontextprotocol/server-github"],
                env: ["GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_...demo"]),
            "linear": server("linear", url: "https://mcp.linear.example.com/mcp", auth: "oauth", enabled: false),
            "browser": server("browser", command: "browser-mcp", plugin: "web-browser"),
        ]

        private static func tools(for name: String) -> [JSONValue] {
            let tools: [(String, String)] =
                switch name {
                case "github":
                    [
                        ("search_issues", "Search issues and pull requests"),
                        ("get_pull_request", "Read a pull request"),
                        ("create_issue", "Open a new issue"), ("list_commits", "List recent commits"),
                    ]
                case "linear":
                    [("list_issues", "List issues in a team"), ("create_issue", "Create an issue")]
                case "browser":
                    [("open_page", "Open a web page"), ("read_page", "Read the page's text")]
                default:
                    [("search", "Search"), ("fetch", "Fetch a result")]
                }
            return tools.map { ["name": .string($0.0), "description": .string($0.1)] }
        }

        private static let catalog: [JSONValue] = [
            [
                "name": "github", "description": "Issues, pull requests and code on GitHub", "transport": "stdio",
                "auth_type": "env", "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"],
                "required_env": [["name": "GITHUB_PERSONAL_ACCESS_TOKEN", "prompt": "GitHub token", "required": true]],
                "needs_install": false,
            ],
            [
                "name": "brave-search", "description": "Search the web with Brave", "transport": "stdio",
                "auth_type": "env", "command": "npx", "args": ["-y", "@brave/brave-search-mcp-server"],
                "required_env": [["name": "BRAVE_API_KEY", "prompt": "Brave Search API key", "required": true]],
                "needs_install": false,
            ],
            [
                "name": "notion", "description": "Pages and databases in your Notion workspace", "transport": "http",
                "auth_type": "oauth", "url": "https://mcp.notion.example.com/mcp", "required_env": [],
                "needs_install": false,
            ],
            [
                "name": "filesystem", "description": "Read and write files in folders you choose", "transport": "stdio",
                "auth_type": "none", "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem"],
                "required_env": [], "needs_install": false,
            ],
        ]
    }
#endif
