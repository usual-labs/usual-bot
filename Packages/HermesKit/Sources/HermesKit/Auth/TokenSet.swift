import Foundation

/// The bearer tokens a gateway issues after browser sign-in.
/// The access token lasts about 15 minutes; the refresh token rotates on every use.
public struct TokenSet: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var provider: String
    public var userID: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, provider: String, userID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.provider = provider
        self.userID = userID
    }

    func expires(within interval: TimeInterval, now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) <= interval
    }
}

/// The JSON body of `/auth/native/token` and `/auth/native/refresh`.
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double
    let provider: String?
    let userId: String?

    var tokenSet: TokenSet {
        TokenSet(
            accessToken: accessToken, refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            provider: provider ?? "", userID: userId ?? "")
    }
}
