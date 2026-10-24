import Foundation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
struct LifecycleTests {
    /// A signed-in model whose sockets the test can count.
    private func makeModel() throws -> (AppModel, SocketLog) {
        let store = MemoryTokenStore()
        try store.save(
            TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            for: testGateway)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let http = ScriptedHTTP { _ in (200, #"{"ticket":"t1"}"#) }
        let sockets = SocketLog()
        let model = AppModel(
            tokenStore: store, http: http, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in
                let socket = FakeSocket()
                sockets.dialled.withLock { $0 += 1 }
                return socket
            })
        return (model, sockets)
    }

    private func waitForSockets(_ count: Int, in sockets: SocketLog) async {
        for _ in 0..<200 where sockets.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func launchShowsTheSplashUntilTheSavedSignInIsRead() async throws {
        let (model, _) = try makeModel()
        #expect(model.isRestoring)
        model.setForeground(false)
        await model.restore()
        #expect(!model.isRestoring)
        #expect(model.session == .signedIn(testGateway))

        // A saved address without a sign-in ends on the connect screen.
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let empty = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (500, "") }, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)))
        #expect(empty.isRestoring)
        await empty.restore()
        #expect(!empty.isRestoring)
        #expect(empty.session == .signedOut)
    }

    @Test func backgroundKeepsTheSocketClosedUntilTheAppReturns() async throws {
        let (model, sockets) = try makeModel()
        model.setForeground(false)
        await model.restore()
        try await Task.sleep(for: .milliseconds(200))
        #expect(sockets.count == 0)

        model.setForeground(true)
        await waitForSockets(1, in: sockets)
        #expect(sockets.count == 1)
    }

    @Test func returningFromTheBackgroundDialsAgain() async throws {
        let (model, sockets) = try makeModel()
        await model.restore()
        await waitForSockets(1, in: sockets)

        model.setForeground(false)
        model.setForeground(true)
        await waitForSockets(2, in: sockets)
        #expect(sockets.count == 2)
        #expect(model.session == .signedIn(testGateway))
    }
}

/// How many sockets the model dialled.
private final class SocketLog: Sendable {
    let dialled = Mutex(0)
    var count: Int { dialled.withLock { $0 } }
}
