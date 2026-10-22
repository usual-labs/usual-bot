import Foundation

/// Holds one gateway's tokens and keeps the access token fresh.
///
/// Refresh tokens rotate and the gateway revokes the whole session when an old one is reused,
/// so at most one refresh runs at a time and every rotation is written to the store at once.
public actor AuthSession {
    public nonisolated let gateway: GatewayAddress
    private var tokens: TokenSet
    private let store: any TokenStore
    private let http: any HTTPTransport
    private let now: @Sendable () -> Date
    private var refreshing: Task<TokenSet, any Error>?

    /// Refresh this long before the access token expires.
    static let refreshMargin: TimeInterval = 60

    public init(
        gateway: GatewayAddress, tokens: TokenSet, store: any TokenStore, http: any HTTPTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gateway = gateway
        self.tokens = tokens
        self.store = store
        self.http = http
        self.now = now
    }

    public var userID: String { tokens.userID }

    /// A valid access token, refreshing first when it is about to expire.
    public func accessToken() async throws -> String {
        if tokens.expires(within: Self.refreshMargin, now: now()) {
            return try await refresh().accessToken
        }
        return tokens.accessToken
    }

    /// Sends a JSON request with the bearer token. A 401 triggers one refresh and one retry.
    func json<T: Decodable & Sendable>(_ type: T.Type, path: String, method: String = "GET") async throws -> T {
        let request = URLRequest.json(gateway.url(path), method: method, bearer: try await accessToken())
        do {
            return try await http.json(T.self, for: request)
        } catch GatewayError.http(status: 401, _) {
            let retry = URLRequest.json(gateway.url(path), method: method, bearer: try await refresh().accessToken)
            return try await http.json(T.self, for: retry)
        }
    }

    /// A single-use, 30-second ticket for opening the JSON-RPC socket.
    func webSocketTicket() async throws -> String {
        struct Ticket: Decodable { let ticket: String }
        return try await json(Ticket.self, path: "/api/auth/ws-ticket", method: "POST").ticket
    }

    /// Rotates the tokens. Concurrent callers share one request.
    @discardableResult
    func refresh() async throws -> TokenSet {
        if let refreshing { return try await refreshing.value }
        let task = Task { try await performRefresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> TokenSet {
        struct Body: Encodable {
            let refreshToken: String
            let provider: String
        }
        let request = URLRequest.json(
            gateway.url("/auth/native/refresh"), method: "POST",
            body: Body(refreshToken: tokens.refreshToken, provider: tokens.provider))
        let fresh: TokenSet
        do {
            fresh = try await http.json(TokenResponse.self, for: request).tokenSet
        } catch GatewayError.http(status: 401, _) {
            // The refresh token is spent or revoked: nothing left to retry with.
            try? store.delete(for: gateway)
            throw GatewayError.signInRequired
        }
        tokens = fresh
        // Persist before anyone uses the new pair, so a relaunch never replays the spent token.
        try? store.save(fresh, for: gateway)
        return fresh
    }

    /// Forgets the tokens on this device.
    public func signOut() {
        try? store.delete(for: gateway)
    }
}
