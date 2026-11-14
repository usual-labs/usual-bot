import Foundation
import Synchronization
import Testing

@testable import HermesKit

struct AuthSessionTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func tokens(access: String = "a0", refresh: String = "r0", expiresIn: TimeInterval) -> TokenSet {
        TokenSet(
            accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(expiresIn), provider: "nous",
            userID: "u1")
    }

    @Test func freshTokenIsUsedAsIs() async throws {
        let http = ScriptedHTTP { _ in
            Issue.record("no request expected"); return (500, "")
        }
        let session = AuthSession(
            gateway: testGateway, tokens: tokens(expiresIn: 600), store: MemoryTokenStore(), http: http,
            now: { [now] in now })
        #expect(try await session.accessToken() == "a0")
    }

    @Test func expiringTokenIsRefreshedAndPersisted() async throws {
        let store = MemoryTokenStore()
        let http = ScriptedHTTP { request in
            #expect(request.url?.path == "/auth/native/refresh")
            #expect(request.jsonBody == ["refresh_token": "r0", "provider": "nous"])
            return (200, tokenJSON(access: "a1", refresh: "r1", expiresAt: 1_000_900))
        }
        let session = AuthSession(
            gateway: testGateway, tokens: tokens(expiresIn: 30), store: store, http: http, now: { [now] in now })

        #expect(try await session.accessToken() == "a1")
        #expect(try store.load(for: testGateway)?.refreshToken == "r1")
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let calls = Mutex(0)
        let http = ScriptedHTTP { _ in
            calls.withLock { $0 += 1 }
            // sleep-ok: a slow server, so the callers overlap
            try await Task.sleep(for: .milliseconds(50))
            return (200, tokenJSON(access: "a1", refresh: "r1", expiresAt: 1_000_900))
        }
        let session = AuthSession(
            gateway: testGateway, tokens: tokens(expiresIn: 0), store: MemoryTokenStore(), http: http,
            now: { [now] in now })

        async let first = session.accessToken()
        async let second = session.accessToken()
        async let third = session.accessToken()
        #expect(try await [first, second, third] == ["a1", "a1", "a1"])
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func rejectedRefreshMeansSignInAgainAndForgetsTokens() async throws {
        let store = MemoryTokenStore()
        try store.save(tokens(expiresIn: 0), for: testGateway)
        let http = ScriptedHTTP { _ in (401, #"{"error":"session_expired"}"#) }
        let session = AuthSession(
            gateway: testGateway, tokens: tokens(expiresIn: 0), store: store, http: http, now: { [now] in now })

        await #expect(throws: GatewayError.signInRequired) { try await session.accessToken() }
        #expect(try store.load(for: testGateway) == nil)
    }

    @Test func unauthorizedRequestRefreshesOnceAndRetries() async throws {
        let http = ScriptedHTTP { request in
            switch (request.url?.path, request.value(forHTTPHeaderField: "Authorization")) {
            case ("/api/auth/ws-ticket", "Bearer a0"): return (401, #"{"detail":"expired"}"#)
            case ("/auth/native/refresh", _): return (200, tokenJSON(access: "a1", refresh: "r1", expiresAt: 1_000_900))
            case ("/api/auth/ws-ticket", "Bearer a1"): return (200, #"{"ticket":"t1","ttl_seconds":30}"#)
            default: return (500, "")
            }
        }
        let session = AuthSession(
            gateway: testGateway, tokens: tokens(expiresIn: 600), store: MemoryTokenStore(), http: http,
            now: { [now] in now })

        #expect(try await session.webSocketTicket() == "t1")
        #expect(
            http.requests.map { $0.url!.path } == [
                "/api/auth/ws-ticket", "/auth/native/refresh", "/api/auth/ws-ticket",
            ])
    }

    // MARK: - Shared with the share extension

    /// The share extension renews the same sign-in on iPhone. Replaying a refresh token it already
    /// spent would make the gateway revoke the whole sign-in, so the newer stored pair is used.
    @Test func aRenewalByAnotherProcessIsAdoptedNotReplayed() async throws {
        let store = MemoryTokenStore()
        try store.save(tokens(access: "a1", refresh: "r1", expiresIn: 600), for: testGateway)
        let http = ScriptedHTTP { _ in
            Issue.record("no request expected"); return (500, "")
        }
        let session = AuthSession(
            gateway: testGateway, tokens: tokens(expiresIn: 0), store: store, http: http, now: { [now] in now })

        #expect(try await session.accessToken() == "a1")
    }

    @Test func aRenewalStartsFromTheNewestStoredRefreshToken() async throws {
        let store = MemoryTokenStore()
        try store.save(tokens(access: "a1", refresh: "r1", expiresIn: 0), for: testGateway)
        let http = ScriptedHTTP { request in
            #expect(request.jsonBody == ["refresh_token": "r1", "provider": "nous"])
            return (200, tokenJSON(access: "a2", refresh: "r2", expiresAt: 1_000_900))
        }
        let session = AuthSession(
            gateway: testGateway, tokens: tokens(expiresIn: 0), store: store, http: http, now: { [now] in now })

        #expect(try await session.accessToken() == "a2")
        #expect(try store.load(for: testGateway)?.refreshToken == "r2")
    }

    @Test func renewalsWaitWhileTheOtherProcessRenews() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "signin-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = MemoryTokenStore(refreshLock: RefreshLock(url: file))
        try store.save(tokens(expiresIn: 0), for: testGateway)
        // The share extension holds the lock: it's renewing.
        let elsewhere = try await RefreshLock(url: file).acquire()
        let requests = Mutex(0)
        let http = ScriptedHTTP { _ in
            requests.withLock { $0 += 1 }
            return (200, tokenJSON(access: "a2", refresh: "r2", expiresAt: 1_000_900))
        }
        let session = AuthSession(
            gateway: testGateway, tokens: tokens(expiresIn: 0), store: store, http: http, now: { [now] in now })

        let renewal = Task { try await session.accessToken() }
        // sleep-ok: nothing to wait for; the renewal must still be waiting after this
        try await Task.sleep(for: .milliseconds(200))
        #expect(requests.withLock { $0 } == 0)
        try store.save(tokens(access: "a1", refresh: "r1", expiresIn: 600), for: testGateway)
        elsewhere.release()

        #expect(try await renewal.value == "a1")
        #expect(requests.withLock { $0 } == 0)
    }

    @Test func theLockIsLetGoForTheNextRenewal() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "signin-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = try await RefreshLock(url: file).acquire()
        first.release()
        let second = try await RefreshLock(url: file).acquire(timeout: .milliseconds(500))
        second.release()
        // Held, it times out instead of waiting for ever.
        let held = try await RefreshLock(url: file).acquire()
        defer { held.release() }
        await #expect(throws: GatewayError.timedOut) {
            try await RefreshLock(url: file).acquire(timeout: .milliseconds(200))
        }
    }
}
