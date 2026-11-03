import Foundation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
struct MCPServerListTests {
    private func list(
        _ http: ScriptedHTTP, channel: JSONRPCChannel? = nil, sessionID: String? = nil, unencrypted: Bool = false
    ) -> MCPServerList {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        return MCPServerList(
            profile: "ops team", auth: { auth }, channel: { channel }, sessionID: { sessionID },
            gatewayIsUnencrypted: { unencrypted }, pollInterval: .zero)
    }

    private nonisolated static let listing = """
        {"servers":[\
        {"name":"github","transport":"stdio","url":null,"command":"/usr/local/bin/npx",\
        "args":["-y","@modelcontextprotocol/server-github"],"env":{"GITHUB_TOKEN":"ghp_...abcd","EMPTY":""},\
        "auth":null,"enabled":true,"tools":null,"source":"config","plugin":null},\
        {"name":"linear","transport":"http","url":"https://mcp.linear.example.com/mcp","command":null,"args":[],\
        "env":{},"auth":"oauth","enabled":false,"tools":null,"source":"config","plugin":null},\
        {"name":"browser","transport":"stdio","url":null,"command":"browser-mcp","args":[],"env":{},"auth":null,\
        "enabled":true,"tools":null,"source":"plugin","plugin":"web-browser"}]}
        """

    private func loaded(_ handler: @escaping ScriptedHTTP.Handler) async -> (MCPServerList, ScriptedHTTP) {
        let http = ScriptedHTTP { request in
            if request.httpMethod == "GET", request.url?.path == "/api/mcp/servers" { return (200, Self.listing) }
            return try await handler(request)
        }
        let apps = list(http)
        await apps.refresh()
        return (apps, http)
    }

    @Test func listsServersForTheProfileWithoutKeepingEnvValues() async throws {
        let (apps, http) = await loaded { _ in (500, "{}") }
        #expect(http.requests.first?.url?.query == "profile=ops%20team")
        #expect(apps.phase == .ready)
        #expect(apps.servers.map(\.name) == ["github", "linear", "browser"])
        let github = apps.servers[0]
        #expect(github.location == "npx @modelcontextprotocol/server-github")
        #expect(github.envNames == ["GITHUB_TOKEN"])
        #expect(!String(reflecting: github).contains("ghp_"))
        #expect(apps.servers[1].location == "mcp.linear.example.com")
        #expect(apps.servers[1].usesSignIn && !apps.servers[1].enabled)
        #expect(apps.servers[2].isFromPlugin && apps.servers[2].plugin == "web-browser")
    }

    @Test func aFailedFirstLoadSaysWhy() async {
        let apps = list(ScriptedHTTP { _ in (500, #"{"detail":"config unreadable"}"#) })
        await apps.refresh()
        #expect(apps.phase == .failed("config unreadable (HTTP 500)"))
    }

    @Test func switchesThroughTheDashboardAndAsksToApply() async throws {
        let (apps, http) = await loaded { _ in (200, #"{"ok":true,"name":"linear","enabled":true}"#) }
        await apps.setEnabled(true, for: apps.servers[1])
        let toggle = try #require(http.requests.last)
        #expect(toggle.httpMethod == "PUT")
        #expect(toggle.url?.path == "/api/mcp/servers/linear/enabled")
        #expect(toggle.jsonBody == ["enabled": true, "profile": "ops team"])
        #expect(apps.servers[1].enabled)
        #expect(apps.needsApply)
    }

    @Test func aRefusedSwitchMovesBack() async {
        let (apps, _) = await loaded { _ in (409, #"{"detail":"config is read-only"}"#) }
        await apps.setEnabled(false, for: apps.servers[0])
        #expect(apps.servers[0].enabled)
        #expect(!apps.needsApply)
        #expect(apps.problem == "Couldn't turn off “github”: config is read-only (HTTP 409)")
    }

    @Test func pluginServersAreLeftAlone() async {
        let (apps, http) = await loaded { _ in (200, "{}") }
        await apps.setEnabled(false, for: apps.servers[2])
        #expect(await !apps.remove(apps.servers[2]))
        #expect(http.requests.count == 1)
    }

    @Test func addsAWebServerWithATokenThatOnlyGoesToTheGateway() async throws {
        let (apps, http) = await loaded { request in
            request.httpMethod == "POST" ? (200, #"{"name":"docs"}"#) : (500, "{}")
        }
        var draft = MCPServerDraft()
        draft.name = " docs "
        draft.url = "https://docs.example.com/mcp"
        draft.auth = .token
        draft.token = "s3cret-token"
        #expect(await apps.add(draft))
        let add = try #require(http.requests.first { $0.httpMethod == "POST" })
        #expect(add.url?.path == "/api/mcp/servers")
        #expect(
            add.jsonBody == [
                "name": "docs", "url": "https://docs.example.com/mcp", "args": [], "auth": "header",
                "bearer_token": "s3cret-token", "profile": "ops team",
            ])
        #expect(apps.needsApply)
        // The list is read again afterwards.
        #expect(http.requests.last?.httpMethod == "GET")
    }

    @Test func addsAProgramWithQuotedArguments() async throws {
        let (apps, http) = await loaded { _ in (200, "{}") }
        var draft = MCPServerDraft()
        draft.name = "notes"
        draft.kind = .program
        draft.command = "uvx"
        draft.arguments = #"notes-mcp --root "/Users/me/My Notes""#
        #expect(await apps.add(draft))
        let add = try #require(http.requests.first { $0.httpMethod == "POST" })
        #expect(
            add.jsonBody == [
                "name": "notes", "command": "uvx", "args": ["notes-mcp", "--root", "/Users/me/My Notes"],
                "auth": "none", "profile": "ops team",
            ])
    }

    @Test func aRefusedAddSaysWhyWithoutTheToken() async {
        let (apps, _) = await loaded { _ in (400, #"{"detail":"Server 'docs' rejected: header s3cret-token"}"#) }
        var draft = MCPServerDraft()
        draft.name = "docs"
        draft.url = "https://docs.example.com/mcp"
        draft.auth = .token
        draft.token = "s3cret-token"
        #expect(await !apps.add(draft))
        #expect(apps.problem == "Couldn't add “docs”: Server 'docs' rejected: header [hidden] (HTTP 400)")
        #expect(!apps.needsApply)
    }

    @Test func onAnUnencryptedGatewayKeysNeedConsentForEachSend() async throws {
        let http = ScriptedHTTP { _ in (200, #"{"ok":true}"#) }
        let apps = list(http, unencrypted: true)
        var draft = MCPServerDraft()
        draft.name = "docs"
        draft.url = "https://docs.example.com/mcp"
        draft.auth = .token
        draft.token = "s3cret-token"
        let entry = MCPCatalogEntry(name: "brave-search", description: "")
        #expect(await !apps.add(draft))
        #expect(await !apps.install(entry, values: ["BRAVE_API_KEY": "key-123"]))
        #expect(http.requests.isEmpty)

        #expect(await apps.add(draft, allowingUnencrypted: true))
        #expect(await apps.install(entry, values: ["BRAVE_API_KEY": "key-123"], allowingUnencrypted: true))
        // Nothing secret, nothing to consent to.
        draft.auth = .none
        #expect(await apps.add(draft))
        #expect(await apps.install(entry, values: [:]))
    }

    @Test func draftsNeedANameAndAWayToReachTheServer() {
        var draft = MCPServerDraft()
        draft.name = "x"
        #expect(!draft.isComplete)
        draft.url = "ftp://example.com"
        #expect(!draft.isComplete)
        draft.url = "https://example.com/mcp"
        #expect(draft.isComplete)
        draft.auth = .token
        #expect(!draft.isComplete)
        draft.kind = .program
        #expect(!draft.isComplete)
        draft.command = "npx"
        #expect(draft.isComplete)
    }

    @Test func removesAndTests() async throws {
        let (apps, http) = await loaded { request in
            if request.url?.path.hasSuffix("/test") == true {
                return (200, #"{"ok":true,"tools":[{"name":"search","description":"Find things"}],"prompts":0}"#)
            }
            return (200, #"{"ok":true}"#)
        }
        await apps.test(apps.servers[0])
        #expect(apps.checks["github"] == .passed([MCPTool(name: "search", description: "Find things")]))
        #expect(http.requests.last?.url?.path == "/api/mcp/servers/github/test")
        #expect(http.requests.last?.timeoutInterval == 120)

        #expect(await apps.remove(apps.servers[0]))
        #expect(http.requests.last?.httpMethod == "DELETE")
        #expect(apps.servers.map(\.name) == ["linear", "browser"])
        #expect(apps.checks["github"] == nil)
        #expect(apps.needsApply)
    }

    @Test func aFailedTestSaysWhy() async {
        let (apps, _) = await loaded { request in
            request.url?.path.contains("github") == true
                ? (200, #"{"ok":false,"error":"Connection closed","tools":[]}"#)
                : (200, #"{"ok":false,"error":"OAuth authentication required — no token found.","tools":[]}"#)
        }
        await apps.test(apps.servers[0])
        #expect(apps.checks["github"] == .failed("It didn't connect: Connection closed"))
        await apps.test(apps.servers[1])
        #expect(apps.checks["linear"] == .failed("Sign in first, then test again."))
    }

    @Test func installsFromTheCatalogWithItsKeys() async throws {
        let catalog = """
            {"entries":[{"name":"brave-search","description":"Search with Brave","transport":"stdio",\
            "auth_type":"env","required_env":[{"name":"BRAVE_API_KEY","prompt":"API key","required":true}],\
            "needs_install":false,"installed":false,"enabled":false}],"diagnostics":[]}
            """
        let (apps, http) = await loaded { request in
            if request.url?.path == "/api/mcp/catalog" { return (200, catalog) }
            return (200, #"{"ok":true,"name":"brave-search","background":false}"#)
        }
        await apps.loadCatalog()
        let entry = try #require(apps.catalog.first)
        #expect(entry.requiredEnv == [MCPCatalogEntry.Key(name: "BRAVE_API_KEY", prompt: "API key")])
        #expect(await apps.install(entry, values: ["BRAVE_API_KEY": "key-123", "UNUSED": ""]))
        let install = try #require(http.requests.first { $0.url?.path == "/api/mcp/catalog/install" })
        #expect(
            install.jsonBody == [
                "name": "brave-search", "env": ["BRAVE_API_KEY": "key-123"], "enable": true, "profile": "ops team",
            ])
        #expect(apps.needsApply)
    }

    @Test func aRefusedInstallLeavesTheKeyOut() async {
        let (apps, _) = await loaded { _ in (400, #"{"detail":"bad value key-123"}"#) }
        let entry = MCPCatalogEntry(name: "brave-search", description: "")
        #expect(await !apps.install(entry, values: ["BRAVE_API_KEY": "key-123"]))
        #expect(apps.problem == "Couldn't add “brave-search”: bad value [hidden] (HTTP 400)")
    }

    @Test func signsInThroughTheBrowserAndWaitsForTheGateway() async throws {
        let polls = Counter()
        let (apps, http) = await loaded { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/mcp/servers/linear/auth"):
                return (
                    200,
                    #"{"flow_id":"f1","status":"authorization_required","authorization_url":"https://linear.example.com/authorize?x=1","error":null}"#
                )
            default:
                return polls.next() < 2
                    ? (200, #"{"flow_id":"f1","status":"authorization_required"}"#)
                    : (200, #"{"flow_id":"f1","status":"approved","tools":[{"name":"list_issues"}]}"#)
            }
        }
        var opened: [URL] = []
        await apps.signIn(apps.servers[1]) { opened.append($0) }
        #expect(opened == [URL(string: "https://linear.example.com/authorize?x=1")!])
        #expect(apps.signIns["linear"] == nil)
        #expect(apps.checks["linear"] == .passed([MCPTool(name: "list_issues")]))
        #expect(http.requests.contains { $0.url?.path == "/api/mcp/oauth/flows/f1" })
        #expect(http.requests.first { $0.httpMethod == "POST" }?.url?.query == "profile=ops%20team")
    }

    @Test func aFailedSignInSaysWhy() async {
        let (apps, _) = await loaded { request in
            request.httpMethod == "POST"
                ? (200, #"{"flow_id":"f2","status":"starting","authorization_url":"https://p.example.com/a"}"#)
                : (200, #"{"flow_id":"f2","status":"error","error":"Provider refused the redirect address"}"#)
        }
        await apps.signIn(apps.servers[1]) { _ in }
        #expect(apps.signIns["linear"] == .failed("Provider refused the redirect address"))
    }

    @Test func cancellingASignInTellsTheGateway() async throws {
        let (apps, http) = await loaded { request in
            switch request.httpMethod {
            case "POST":
                (
                    200,
                    #"{"flow_id":"f3","status":"authorization_required","authorization_url":"https://p.example.com/a"}"#
                )
            case "DELETE": (200, #"{"ok":true,"status":"error"}"#)
            default: (200, #"{"flow_id":"f3","status":"authorization_required"}"#)
            }
        }
        let server = apps.servers[1]
        let waiting = Task { await apps.signIn(server) { _ in } }
        try await waitUntilOnMain { apps.signIns["linear"] == .waiting }
        await apps.cancelSignIn(server)
        await waiting.value
        #expect(apps.signIns["linear"] == nil)
        #expect(http.requests.contains { $0.httpMethod == "DELETE" && $0.url?.path == "/api/mcp/oauth/flows/f3" })
    }

    @Test func appliesThroughTheAgentsChatWithConsent() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let apps = list(ScriptedHTTP { _ in (200, "{}") }, channel: channel, sessionID: "live-7")
        #expect(apps.canApplyNow)
        async let applied: Void = apps.applyNow()
        let params = try await gateway.answer(
            0, method: "reload.mcp", result: ["status": "reloaded", "unavailable": ["linear"]])
        await applied
        #expect(params == ["session_id": "live-7", "confirm": true])
        #expect(!apps.needsApply)
        #expect(apps.notice == "Applied, but these didn't connect: linear.")
    }

    @Test func theDemoRunsInMemory() async throws {
        let apps = MCPServerList.demo(gateway: testGateway)
        await apps.refresh()
        #expect(apps.servers.map(\.name) == ["browser", "github", "linear"])
        #expect(apps.servers.map(\.enabled) == [true, true, false])
        #expect(apps.servers[0].isFromPlugin)
        await apps.setEnabled(true, for: apps.servers[2])
        #expect(apps.problem == nil && apps.servers[2].enabled)
        await apps.loadCatalog()
        let notion = try #require(apps.catalog.first { $0.name == "notion" })
        #expect(await apps.install(notion, values: [:]))
        #expect(apps.servers.contains { $0.name == "notion" && $0.usesSignIn })
        #expect(apps.canApplyNow)
        await apps.applyNow()
        #expect(!apps.needsApply)
    }

    @Test func applyingWithoutAnOpenChatSaysWhatToDo() async {
        let apps = list(ScriptedHTTP { _ in (200, "{}") })
        #expect(!apps.canApplyNow)
        await apps.applyNow()
        #expect(apps.problem == "Open a chat with this Bot first, then apply.")
    }
}

/// Counts calls from a fake's handler.
private final class Counter: Sendable {
    private let count = Mutex(0)

    /// The number of earlier calls.
    func next() -> Int {
        count.withLock { count in
            defer { count += 1 }
            return count
        }
    }
}
