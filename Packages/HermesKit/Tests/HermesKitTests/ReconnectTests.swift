import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// Coming back to the app, the chat on screen takes input once its own session answers, not after
/// the push plugin's settings and the roster.
@MainActor
struct ReconnectTests {
    /// Answers every request on `socket`, except `profiles.list` when `withholdingRoster`.
    private func serve(_ socket: FakeSocket, withholdingRoster: Bool = false) -> Task<Void, Never> {
        socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"replay_epoch":"e"}}}"#)
        return Task.detached {
            var seen = 0
            while !Task.isCancelled {
                let sent = socket.sent
                for frame in sent[seen...] where frame["method"] != nil {
                    let result: JSONValue
                    switch frame["method"]?.stringValue {
                    case "profiles.list":
                        if withholdingRoster { continue }
                        result = ["profiles": [["name": "scout", "canonical_session": ["id": "stored-1"]]]]
                    case "groups.list": result = ["rooms": []]
                    case "session.resume": result = ["session_id": "live-1", "running": false, "messages": []]
                    default: result = [:]
                    }
                    let reply: JSONValue = ["jsonrpc": "2.0", "id": frame["id"] ?? .null, "result": result]
                    socket.deliver(String(decoding: try! JSONEncoder().encode(reply), as: UTF8.self))
                }
                seen = sent.count
                // sleep-ok: the fake socket has no signal for a new frame
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    @Test func theChatOnScreenReattachesBeforeTheRosterAndPushSettingsAnswer() async throws {
        let store = MemoryTokenStore()
        try store.save(
            TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "basic",
                userID: "u1"), for: testGateway)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let http = ScriptedHTTP { request in
            if request.url?.path().hasSuffix("/settings") == true {
                // sleep-ok: a push plugin that never answers; the chat mustn't wait for it
                try await Task.sleep(for: .seconds(60))
            }
            return (200, #"{"ticket":"t1"}"#)
        }
        let first = FakeSocket()
        let second = FakeSocket()
        let sockets = Mutex([first, second])
        let model = AppModel(
            tokenStore: store, http: http, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in sockets.withLock { $0.removeFirst() } })
        let server = serve(first)
        defer {
            server.cancel()
            model.signOut()
        }
        model.visibleContactID = "scout"
        await model.restore()
        try await waitUntilOnMain { model.threads["scout"]?.isAttached == true }
        let thread = try #require(model.threads["scout"])

        let quiet = serve(second, withholdingRoster: true)
        defer { quiet.cancel() }
        model.reconnect()
        try await waitUntilOnMain { second.sent.contains { $0["method"] == "session.resume" } }
        try await waitUntilOnMain { thread.isAttached }

        #expect(model.rosterReads == 1)
    }
}
