import Foundation

/// The public `GET /api/status` readout: just what the client needs to pick a sign-in flow.
public struct GatewayStatus: Decodable, Sendable, Equatable {
    public var version: String?
    public var authRequired: Bool
    public var authFlows: [String]

    /// System browser + loopback redirect + PKCE (RFC 8252), the flow this app uses.
    public var supportsNativeSignIn: Bool { authFlows.contains("native_pkce") }

    public init(version: String? = nil, authRequired: Bool, authFlows: [String]) {
        self.version = version
        self.authRequired = authRequired
        self.authFlows = authFlows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        authRequired = (try? container.decodeIfPresent(Bool.self, forKey: .authRequired)) ?? false
        authFlows = (try? container.decodeIfPresent([String].self, forKey: .authFlows)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case version, authRequired, authFlows
    }

    static func fetch(_ gateway: GatewayAddress, http: any HTTPTransport) async throws -> GatewayStatus {
        try await http.json(GatewayStatus.self, for: .json(gateway.url("/api/status")))
    }
}
