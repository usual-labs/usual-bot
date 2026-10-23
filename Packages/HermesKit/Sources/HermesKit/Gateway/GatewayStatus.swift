import Foundation

/// The public `GET /api/status` readout: what the client needs to pick a sign-in flow, plus the
/// version and overall health the Machine tab shows.
public struct GatewayStatus: Decodable, Sendable, Equatable {
    public var version: String?
    public var authRequired: Bool
    public var authFlows: [String]
    /// `ok`, or `degraded` when some component (a platform, the scheduler) is unhealthy.
    public var overall: String?

    /// System browser + loopback redirect + PKCE (RFC 8252), the flow this app uses.
    public var supportsNativeSignIn: Bool { authFlows.contains("native_pkce") }

    public init(version: String? = nil, authRequired: Bool, authFlows: [String], overall: String? = nil) {
        self.version = version
        self.authRequired = authRequired
        self.authFlows = authFlows
        self.overall = overall
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        authRequired = (try? container.decodeIfPresent(Bool.self, forKey: .authRequired)) ?? false
        authFlows = (try? container.decodeIfPresent([String].self, forKey: .authFlows)) ?? []
        overall = try? container.decodeIfPresent(String.self, forKey: .overall)
    }

    private enum CodingKeys: String, CodingKey {
        case version, authRequired, authFlows, overall
    }

    static func fetch(_ gateway: GatewayAddress, http: any HTTPTransport) async throws -> GatewayStatus {
        try await http.json(GatewayStatus.self, for: .json(gateway.url("/api/status")))
    }
}

/// What the Machine tab shows about the gateway.
public struct GatewayDetails: Equatable, Sendable {
    public var version: String?
    /// `nil` when the gateway didn't say.
    public var isHealthy: Bool?
    /// Who you're signed in as: a name or email from the gateway's identity provider.
    public var account: String?
}

/// `GET /api/auth/me`.
struct SignedInUser: Decodable, Sendable {
    let displayName: String?
    let email: String?

    var label: String? {
        displayName?.nonBlank ?? email?.nonBlank
    }
}
