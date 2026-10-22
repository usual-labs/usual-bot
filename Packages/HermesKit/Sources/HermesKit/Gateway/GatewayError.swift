import Foundation

/// Everything that can go wrong talking to a gateway, in terms the UI can show.
public enum GatewayError: Error, Equatable, Sendable {
    case unreachable(String)
    case http(status: Int, message: String?)
    case invalidResponse
    /// The gateway doesn't offer browser sign-in for native apps (no `native_pkce` in `/api/status`).
    case signInUnsupported
    /// The stored session is gone or was rejected; the user has to sign in again.
    case signInRequired
    case signInFailed(String)
    case cancelled
    case timedOut
    case disconnected
    case rpc(code: Int, message: String)
}

extension GatewayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreachable(let detail):
            return String(localized: "Can't reach the gateway. \(detail)")
        case .http(let status, let message):
            return message.map { "\($0) (HTTP \(status))" } ?? String(localized: "The gateway answered HTTP \(status).")
        case .invalidResponse:
            return String(localized: "The gateway sent a response Usual Bot doesn't understand.")
        case .signInUnsupported:
            return String(localized: "This gateway doesn't offer browser sign-in for apps. Update Hermes on it.")
        case .signInRequired:
            return String(localized: "Your sign-in expired. Sign in again.")
        case .signInFailed(let detail):
            return String(localized: "Sign-in didn't finish: \(detail)")
        case .cancelled:
            return String(localized: "Sign-in was cancelled.")
        case .timedOut:
            return String(localized: "The gateway took too long to answer.")
        case .disconnected:
            return String(localized: "The connection to the gateway closed.")
        case .rpc(_, let message):
            return message
        }
    }
}
