import Foundation
import Testing

@testable import HermesKit

struct PKCETests {
    @Test func challengeIsBase64URLSHA256OfVerifier() {
        // Expected value computed independently:
        // printf '%s' <verifier> | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '='
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mJ92K9qQGNTtsyRu8zCd8VQ7wXhh4c")
        #expect(pkce.challenge == "QKzuZGG_NZUOtv7Cx9gLg72acAREEs7NKcdfeUKYY2o")
    }

    @Test func randomVerifierHasRFCLengthAndAlphabet() {
        let verifier = PKCE.random().verifier
        #expect(verifier.count == 43)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(PKCE.random().verifier != verifier)
    }
}

struct NativeSignInTests {
    @Test func authorizeURLCarriesPKCEAndLoopbackRedirect() throws {
        let url = NativeSignIn.authorizeURL(
            gateway: testGateway, challenge: "chal", redirectURI: "http://127.0.0.1:5555/callback", state: "st")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/auth/native/authorize")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(
            query == [
                "code_challenge": "chal", "code_challenge_method": "S256",
                "redirect_uri": "http://127.0.0.1:5555/callback", "state": "st",
            ])
    }

    @Test func callbackNeedsMatchingStateAndCode() throws {
        let good = [URLQueryItem(name: "code", value: "c1"), URLQueryItem(name: "state", value: "st")]
        #expect(try NativeSignIn.code(from: good, expectedState: "st") == "c1")

        let forged = [URLQueryItem(name: "code", value: "c1"), URLQueryItem(name: "state", value: "other")]
        #expect(throws: GatewayError.self) { try NativeSignIn.code(from: forged, expectedState: "st") }

        let noCode = [URLQueryItem(name: "state", value: "st")]
        #expect(throws: GatewayError.self) { try NativeSignIn.code(from: noCode, expectedState: "st") }
    }

    @Test func redeemPostsCodeAndVerifier() async throws {
        let http = ScriptedHTTP { _ in (200, tokenJSON(access: "a1", refresh: "r1", expiresAt: 2_000_000_000)) }
        let tokens = try await NativeSignIn.redeem(code: "c1", verifier: "v1", gateway: testGateway, http: http)

        #expect(
            tokens
                == TokenSet(
                    accessToken: "a1", refreshToken: "r1", expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                    provider: "nous", userID: "u1"))
        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "http://100.101.102.103:9119/auth/native/token")
        #expect(request.httpMethod == "POST")
        #expect(request.jsonBody == ["code": "c1", "code_verifier": "v1"])
    }

    @Test func expiredCodeSurfacesGatewayMessage() async {
        let http = ScriptedHTTP { _ in (400, #"{"detail":"Invalid or expired authorization code."}"#) }
        await #expect(throws: GatewayError.http(status: 400, message: "Invalid or expired authorization code.")) {
            try await NativeSignIn.redeem(code: "c", verifier: "v", gateway: testGateway, http: http)
        }
    }
}

struct LoopbackReceiverTests {
    @Test func catchesTheCallbackAndAnswersWithAPage() async throws {
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.stop() }
        #expect(receiver.port > 0)
        #expect(receiver.redirectURI == "http://127.0.0.1:\(receiver.port)/callback")

        async let query = receiver.waitForCallback(timeout: .seconds(5))
        let (_, notFound) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(receiver.port)/favicon.ico")!)
        #expect((notFound as? HTTPURLResponse)?.statusCode == 404)
        let (page, response) = try await URLSession.shared.data(
            from: URL(string: "\(receiver.redirectURI)?code=c%201&state=s1")!)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: page, as: UTF8.self).contains("You're signed in"))
        #expect(
            try await query == [URLQueryItem(name: "code", value: "c 1"), URLQueryItem(name: "state", value: "s1")])
    }

    @Test func cancelEndsTheWait() async throws {
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.stop() }
        receiver.cancel()
        await #expect(throws: GatewayError.cancelled) { try await receiver.waitForCallback(timeout: .seconds(5)) }
    }

    @Test func timesOut() async throws {
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.stop() }
        await #expect(throws: GatewayError.timedOut) { try await receiver.waitForCallback(timeout: .milliseconds(50)) }
    }

    @Test func parsesOnlyGETRequestLines() {
        let get = LoopbackReceiver.requestTarget(in: Data("GET /callback?code=x HTTP/1.1\r\nHost: a\r\n\r\n".utf8))
        #expect(get?.path == "/callback")
        #expect(LoopbackReceiver.requestTarget(in: Data("POST /callback HTTP/1.1\r\n\r\n".utf8)) == nil)
        #expect(LoopbackReceiver.requestTarget(in: Data("garbage".utf8)) == nil)
    }
}
