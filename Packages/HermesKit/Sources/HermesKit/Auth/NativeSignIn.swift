import Foundation

/// Shows the gateway's sign-in page to the user. The Mac app opens the default browser;
/// the iPhone app uses an in-app web authentication sheet.
@MainActor
public protocol SignInPresenter: AnyObject {
    /// Opens `url`. Calls `onCancel` if the user closes the sign-in page without finishing.
    func present(_ url: URL, onCancel: @escaping @MainActor () -> Void)
    /// Closes the sign-in page if the presenter can, and brings the app back to the front.
    func dismiss()
}

/// Browser sign-in to a gated gateway (RFC 8252): the gateway brokers the identity provider and
/// returns a one-time code to a loopback redirect; the app redeems it with its PKCE verifier.
enum NativeSignIn {
    @MainActor
    static func run(
        gateway: GatewayAddress, http: any HTTPTransport, presenter: any SignInPresenter,
        timeout: Duration = .seconds(600)
    ) async throws -> TokenSet {
        let pkce = PKCE.random()
        let state = PKCE.randomToken()
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.stop() }

        let authorize = authorizeURL(
            gateway: gateway, challenge: pkce.challenge, redirectURI: receiver.redirectURI, state: state)
        presenter.present(authorize, onCancel: { receiver.cancel() })
        defer { presenter.dismiss() }

        let query = try await receiver.waitForCallback(timeout: timeout)
        let code = try code(from: query, expectedState: state)
        return try await redeem(code: code, verifier: pkce.verifier, gateway: gateway, http: http)
    }

    /// `/auth/native/authorize` takes no client ID or scope; the gateway picks its only provider,
    /// or shows a chooser when it has several.
    static func authorizeURL(gateway: GatewayAddress, challenge: String, redirectURI: String, state: String) -> URL {
        var components = URLComponents(url: gateway.url("/auth/native/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// The redirect must echo our `state` (CSRF protection) and carry a code.
    static func code(from query: [URLQueryItem], expectedState: String) throws -> String {
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        if let error = value("error") { throw GatewayError.signInFailed(error) }
        guard value("state") == expectedState else {
            throw GatewayError.signInFailed(String(localized: "the browser returned an unexpected response"))
        }
        guard let code = value("code"), !code.isEmpty else {
            throw GatewayError.signInFailed(String(localized: "the gateway didn't return a code"))
        }
        return code
    }

    static func redeem(code: String, verifier: String, gateway: GatewayAddress, http: any HTTPTransport)
        async throws -> TokenSet
    {
        struct Body: Encodable {
            let code: String
            let codeVerifier: String
        }
        let request = URLRequest.json(
            gateway.url("/auth/native/token"), method: "POST", body: Body(code: code, codeVerifier: verifier))
        return try await http.json(TokenResponse.self, for: request).tokenSet
    }
}
