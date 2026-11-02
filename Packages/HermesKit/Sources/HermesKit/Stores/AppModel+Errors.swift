import Foundation

extension AppModel {
    /// Like `describe(_:)`, but says what to check when a tailnet gateway can't be reached: the
    /// device usually isn't on the tailnet.
    static func describe(_ error: any Error, for gateway: GatewayAddress) -> String {
        if case .unreachable = error as? GatewayError, gateway.isTailnet {
            return String(
                localized:
                    "Can't reach \(gateway.displayName). It's a Tailscale address, so check that Tailscale is on and signed in on this device."
            )
        }
        return describe(error)
    }

    /// An error in words for the UI.
    public static func describe(_ error: any Error) -> String {
        switch error {
        case let error as GatewayAddress.ParseError:
            switch error {
            case .empty: return String(localized: "Enter your gateway's address.")
            case .invalid: return String(localized: "That doesn't look like a gateway address.")
            case .insecureHTTP(let host):
                return String(
                    localized: "\(host) is on the public internet, so use https:// to keep your sign-in private.")
            }
        case let error as GatewayError:
            return error.errorDescription ?? String(describing: error)
        default:
            return error.localizedDescription
        }
    }
}
