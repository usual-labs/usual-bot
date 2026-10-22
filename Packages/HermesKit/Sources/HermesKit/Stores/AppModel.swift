import Foundation
import Observation
import os

/// The app's top-level state: which gateway it's signed in to, whether the socket is up,
/// and the contacts it reports.
@MainActor
@Observable
public final class AppModel {
    public enum Session: Equatable {
        case signedOut
        case signingIn(GatewayAddress)
        case signedIn(GatewayAddress)
    }

    public enum Link: Equatable {
        case connecting
        case online(GatewayReady.Dialect)
        /// Lost the gateway; retrying in the background.
        case offline(String)
    }

    public private(set) var session: Session = .signedOut
    public private(set) var link: Link = .connecting
    public private(set) var contacts: [Contact] = []
    /// The last sign-in or connection problem, for the connect screen.
    public private(set) var problem: String?
    /// What the user last typed into the gateway field.
    public var gatewayInput: String

    private let tokenStore: any TokenStore
    private let http: any HTTPTransport
    private let makeSocket: GatewayConnector.SocketFactory
    private let defaults: UserDefaults
    private var auth: AuthSession?
    private var signInTask: Task<Void, Never>?
    private var linkTask: Task<Void, Never>?

    private static let gatewayKey = "gatewayAddress"
    private static let rosterInterval: Duration = .seconds(5)
    private static let log = Logger(subsystem: "UsualBot", category: "app")

    public convenience init() {
        self.init(tokenStore: KeychainTokenStore(), http: URLSession.shared, defaults: .standard)
    }

    init(
        tokenStore: any TokenStore, http: any HTTPTransport, defaults: UserDefaults,
        makeSocket: @escaping GatewayConnector.SocketFactory = { URLSessionWebSocket(url: $0) }
    ) {
        self.tokenStore = tokenStore
        self.http = http
        self.defaults = defaults
        self.makeSocket = makeSocket
        gatewayInput = defaults.string(forKey: Self.gatewayKey) ?? ""
    }

    /// Resumes the saved session, if this device has one.
    public func restore() {
        guard case .signedOut = session,
            let saved = defaults.string(forKey: Self.gatewayKey),
            let gateway = try? GatewayAddress(parsing: saved),
            let tokens = try? tokenStore.load(for: gateway)
        else { return }
        begin(AuthSession(gateway: gateway, tokens: tokens, store: tokenStore, http: http))
    }

    /// Signs in to the gateway typed into `gatewayInput` through the browser.
    public func signIn(presenter: any SignInPresenter) {
        problem = nil
        let gateway: GatewayAddress
        do {
            gateway = try GatewayAddress(parsing: gatewayInput)
        } catch {
            problem = Self.describe(error)
            return
        }
        session = .signingIn(gateway)
        signInTask = Task {
            do {
                let status = try await GatewayStatus.fetch(gateway, http: http)
                guard status.supportsNativeSignIn else { throw GatewayError.signInUnsupported }
                let tokens = try await NativeSignIn.run(gateway: gateway, http: http, presenter: presenter)
                try? tokenStore.save(tokens, for: gateway)
                defaults.set(gateway.baseURL.absoluteString, forKey: Self.gatewayKey)
                gatewayInput = gateway.baseURL.absoluteString
                begin(AuthSession(gateway: gateway, tokens: tokens, store: tokenStore, http: http))
            } catch {
                if case .signingIn = session { session = .signedOut }
                if (error as? GatewayError) != .cancelled { problem = Self.describe(error) }
            }
        }
    }

    public func cancelSignIn() {
        signInTask?.cancel()
    }

    public func signOut() {
        linkTask?.cancel()
        signInTask?.cancel()
        if let auth { Task { await auth.signOut() } }
        auth = nil
        contacts = []
        link = .connecting
        session = .signedOut
    }

    // MARK: - Connection

    private func begin(_ auth: AuthSession) {
        self.auth = auth
        session = .signedIn(auth.gateway)
        link = .connecting
        linkTask?.cancel()
        linkTask = Task { await stayConnected(auth) }
    }

    /// Connects, refreshes the roster every few seconds, and reconnects with backoff when the
    /// socket drops. Ends when the task is cancelled or the gateway rejects the session.
    private func stayConnected(_ auth: AuthSession) async {
        let connector = GatewayConnector(auth: auth, makeSocket: makeSocket)
        var attempt = 0
        while !Task.isCancelled {
            do {
                let (channel, ready) = try await connector.connect()
                attempt = 0
                link = .online(ready.dialect)
                defer { Task { await channel.close() } }
                while !Task.isCancelled {
                    try await refreshRoster(on: channel)
                    try await Task.sleep(for: Self.rosterInterval)
                }
            } catch GatewayError.signInRequired {
                problem = GatewayError.signInRequired.errorDescription
                signOut()
                return
            } catch {
                guard !Task.isCancelled else { return }
                link = .offline(Self.describe(error))
                Self.log.error("Gateway link dropped: \(Self.describe(error), privacy: .public)")
                try? await Task.sleep(for: Backoff.delay(attempt: attempt))
                attempt += 1
                link = .connecting
            }
        }
    }

    private func refreshRoster(on channel: JSONRPCChannel) async throws {
        let result = try await channel.call("profiles.list", params: ["include_sessions": true])
        let list = try result.decode(ProfileList.self)
        contacts = list.profiles.compactMap(Contact.init(profile:))
    }

    static func describe(_ error: any Error) -> String {
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
