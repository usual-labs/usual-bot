import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// A gateway's answers for one Bot Chat's read state, scripted per route.
private final class ReadGateway: Sendable {
    struct State {
        var revision = 3
        /// `nil` is the null of a chat never marked.
        var lastReadAt: Double?
        /// The detail leaves `last_read_at` out, as a gateway from before read times does.
        var keepsReadTimes = true
        /// PATCHes to refuse as a conflict before accepting one.
        var conflicts = 0
    }

    private final class Store: Sendable {
        let state = Mutex(State())
    }

    private let store = Store()
    let http: ScriptedHTTP

    init() {
        http = ScriptedHTTP { [store] request in
            store.state.withLock { state in Self.answer(request, &state) }
        }
    }

    func change(_ body: (inout State) -> Void) {
        store.state.withLock { body(&$0) }
    }

    var paths: [String] {
        http.requests.map { "\($0.httpMethod ?? "GET") \($0.url?.path() ?? "")" }
    }

    private static func answer(_ request: URLRequest, _ state: inout State) -> (Int, String) {
        if request.url?.path().hasSuffix("/mutation-snapshot") == true {
            return (200, #"{"session_id":"chat-1","exists":true,"runtime_revision":\#(state.revision)}"#)
        }
        if request.httpMethod == "PATCH" {
            state.revision += 1
            if state.conflicts > 0 {
                state.conflicts -= 1
                return (409, #"{"detail":"revision_conflict"}"#)
            }
            return (200, #"{"ok":true,"revision":\#(state.revision),"operation":"sidebar","unread":false}"#)
        }
        let readAt = state.lastReadAt.map { String($0) } ?? "null"
        let field = state.keepsReadTimes ? #","last_read_at":\#(readAt)"# : ""
        return (200, #"{"id":"chat-1","system_prompt":"…"\#(field)}"#)
    }
}

@MainActor
@Suite("Read state shared through the gateway")
struct ReadSyncTests {
    private func reply(_ text: String, at seconds: Double) -> HistoryMessage {
        HistoryMessage(role: "assistant", text: text, timestamp: seconds)
    }

    /// A chat with replies at 100 and 200, the last two unread here.
    private func makeSync(unread: Int = 2) -> (ReadSync, ChatThread, ReadGateway, Box) {
        let gateway = ReadGateway()
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "basic",
                userID: "u1"),
            store: MemoryTokenStore(), http: gateway.http)
        let thread = ChatThread.sample(
            "ops",
            state: ThreadState(
                history: [
                    HistoryMessage(role: "user", text: "Status?", timestamp: 50),
                    reply("Deploying", at: 100), reply("Done", at: 200),
                ], running: false))
        thread.unreadCount = unread
        let chat = ReadSync.Chat(thread: thread, storedID: "chat-1", profile: "ops")
        let sync = ReadSync(auth: { auth }, chats: { [chat] })
        let box = Box()
        sync.cleared = { box.cleared.append($0) }
        return (sync, thread, gateway, box)
    }

    private final class Box {
        var cleared: [Contact.ID] = []
    }

    // MARK: - Reading here

    @Test func readingAChatTellsTheGatewayOnce() async throws {
        let (sync, thread, gateway, _) = makeSync()
        sync.markRead("ops")
        await sync.settled()
        #expect(gateway.paths == ["GET /api/sessions/chat-1/mutation-snapshot", "PATCH /api/sessions/chat-1"])
        let body = try #require(gateway.http.requests.last?.jsonBody)
        #expect(body["unread"] == false)
        #expect(body["expected_revision"] == 3)
        #expect(body["profile"] == "ops")
        #expect(body["request_id"]?.stringValue?.isEmpty == false)
        #expect(thread.readOnGateway == Date(timeIntervalSince1970: 200))

        // Nothing new since: no second write.
        sync.markRead("ops")
        await sync.settled()
        #expect(gateway.http.requests.count == 2)
    }

    @Test func aNewReplyIsWrittenAtTheRevisionTheLastWriteLeft() async throws {
        let (sync, thread, gateway, _) = makeSync()
        sync.markRead("ops")
        await sync.settled()
        thread.state = ThreadState(history: [reply("Done", at: 200), reply("Also this", at: 300)], running: false)
        sync.markRead("ops")
        await sync.settled()
        #expect(gateway.paths.filter { $0.hasSuffix("mutation-snapshot") }.count == 1)
        #expect(gateway.http.requests.last?.jsonBody?["expected_revision"] == 4)
    }

    @Test func aWriteThatLostARaceIsTriedOnceMore() async throws {
        let (sync, thread, gateway, _) = makeSync()
        gateway.change { $0.conflicts = 1 }
        sync.markRead("ops")
        await sync.settled()
        #expect(
            gateway.paths == [
                "GET /api/sessions/chat-1/mutation-snapshot", "PATCH /api/sessions/chat-1",
                "GET /api/sessions/chat-1/mutation-snapshot", "PATCH /api/sessions/chat-1",
            ])
        #expect(gateway.http.requests.last?.jsonBody?["expected_revision"] == 4)
        #expect(thread.readOnGateway != nil)
    }

    // MARK: - Reading elsewhere

    @Test func aChatReadElsewhereStopsCountingHere() async {
        let (sync, thread, gateway, box) = makeSync()
        gateway.change { $0.lastReadAt = 250 }
        sync.somethingChanged()
        await sync.settled()
        #expect(thread.unreadCount == 0)
        #expect(box.cleared == ["ops"])
        #expect(gateway.paths == ["GET /api/sessions/chat-1/mutation-snapshot", "GET /api/sessions/chat-1"])
    }

    @Test func aReplyAfterTheReadStaysUnread() async {
        let (sync, thread, gateway, box) = makeSync()
        gateway.change { $0.lastReadAt = 150 }
        sync.somethingChanged()
        await sync.settled()
        #expect(thread.unreadCount == 1)
        #expect(box.cleared.isEmpty)
    }

    @Test func theWholeRecordIsReadOnlyWhenTheRevisionMoved() async {
        let (sync, _, gateway, _) = makeSync()
        gateway.change { $0.lastReadAt = 150 }
        sync.somethingChanged()
        await sync.settled()
        sync.somethingChanged()
        await sync.settled()
        #expect(gateway.paths.filter { $0 == "GET /api/sessions/chat-1" }.count == 1)

        gateway.change { $0.revision = 9 }
        sync.somethingChanged()
        await sync.settled()
        #expect(gateway.paths.filter { $0 == "GET /api/sessions/chat-1" }.count == 2)
    }

    @Test func markedUnreadElsewhereLeavesTheCountAlone() async {
        let (sync, thread, gateway, _) = makeSync()
        gateway.change { $0.lastReadAt = 0 }
        sync.somethingChanged()
        await sync.settled()
        #expect(thread.unreadCount == 2)
    }

    @Test func aChatWithNothingUnreadIsLookedAtOnceItHasSomething() async {
        let (sync, thread, gateway, _) = makeSync(unread: 0)
        gateway.change { $0.lastReadAt = 250 }
        sync.somethingChanged()
        await sync.settled()
        #expect(gateway.http.requests.isEmpty)

        thread.unreadCount = 1
        sync.look()
        await sync.settled()
        #expect(thread.unreadCount == 0)
    }

    @Test func aGatewayWithoutReadTimesIsLeftAlone() async {
        let (sync, thread, gateway, _) = makeSync()
        gateway.change { $0.keepsReadTimes = false }
        sync.somethingChanged()
        await sync.settled()
        #expect(sync.isUnsupported)
        #expect(thread.unreadCount == 2)

        sync.markRead("ops")
        await sync.settled()
        #expect(gateway.http.requests.count == 2)
    }
}

@MainActor
@Suite("Telling the app a chat was read")
struct ChatReadTests {
    private func makeChat(visible: Bool) -> (ChatThread, Counter) {
        let thread = ChatThread.sample("forge", state: ThreadState())
        let counter = Counter()
        thread.wasRead = { counter.count += 1 }
        thread.isVisible = visible
        return (thread, counter)
    }

    private final class Counter {
        var count = 0
    }

    private func reply(_ thread: ChatThread) {
        thread.apply(GatewayEvent(type: "message.start", sessionID: "sample", seq: nil, payload: [:]))
        thread.apply(GatewayEvent(type: "message.complete", sessionID: "sample", seq: nil, payload: ["text": "Done"]))
    }

    @Test func aReplyOnScreenCountsAsRead() {
        let (thread, counter) = makeChat(visible: true)
        let opened = counter.count
        reply(thread)
        #expect(counter.count == opened + 1)
        #expect(thread.newestUnreadable != nil)
    }

    @Test func aReplyOffScreenDoesnt() {
        let (thread, counter) = makeChat(visible: false)
        reply(thread)
        #expect(counter.count == 0)
        #expect(thread.unreadCount == 1)
    }

    @Test func openingAChatCountsAsRead() {
        let (thread, counter) = makeChat(visible: false)
        reply(thread)
        thread.isVisible = true
        #expect(counter.count == 1)
        #expect(thread.unreadCount == 0)
    }
}

/// The app itself, signed in to a scripted gateway, sharing a chat's read state.
@MainActor
struct AppReadSyncTests {
    private func serve(_ socket: FakeSocket) -> Task<Void, Never> {
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
                        result = ["profiles": [["name": "scout", "canonical_session": ["id": "stored-1"]]]]
                    case "groups.list": result = ["rooms": []]
                    case "session.resume":
                        result = [
                            "session_id": "live-1", "running": false,
                            "messages": [["role": "assistant", "text": "Done", "timestamp": 200]],
                        ]
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

    private func signedIn() async throws -> (AppModel, ChatThread, FakeSocket, ScriptedHTTP, Task<Void, Never>) {
        let store = MemoryTokenStore()
        try store.save(
            TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "basic",
                userID: "u1"), for: testGateway)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let socket = FakeSocket()
        let http = ScriptedHTTP { request in
            let path = request.url?.path() ?? ""
            if path.hasSuffix("/mutation-snapshot") { return (200, #"{"runtime_revision":7}"#) }
            if request.httpMethod == "PATCH" { return (200, #"{"ok":true,"revision":8}"#) }
            // Read on another device a minute from now, after this one last had the chat on screen.
            let readAt = Date.now.timeIntervalSince1970 + 60
            if path == "/api/sessions/stored-1" { return (200, #"{"id":"stored-1","last_read_at":\#(readAt)}"#) }
            return (200, #"{"ticket":"t1"}"#)
        }
        let model = AppModel(
            tokenStore: store, http: http, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in socket })
        let server = serve(socket)
        await model.restore()
        try await waitUntilOnMain { model.contacts.contains { $0.id == "scout" } }
        let contact = try #require(model.contacts.first { $0.id == "scout" })
        let thread = model.thread(for: contact)
        model.openThread(for: contact)
        try await waitUntilOnMain { thread.isAttached }
        return (model, thread, socket, http, server)
    }

    private nonisolated func sessionRequests(_ http: ScriptedHTTP) -> [String] {
        http.requests.map { "\($0.httpMethod ?? "GET") \($0.url?.path() ?? "")" }.filter {
            $0.contains("/api/sessions")
        }
    }

    @Test func aChatReadOnAnotherDeviceClearsHereWhenTheGatewaySaysSomethingChanged() async throws {
        let (model, thread, socket, http, server) = try await signedIn()
        defer {
            server.cancel()
            model.signOut()
        }
        var cleared: [Contact.ID?] = []
        model.alertsCleared = { cleared.append($0) }
        thread.unreadCount = 1
        socket.deliver(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"sessions.changed","payload":{}}}"#)
        try await waitUntilOnMain { thread.unreadCount == 0 }
        #expect(cleared == ["scout"])
        #expect(sessionRequests(http).contains("GET /api/sessions/stored-1"))
    }

    @Test func openingAChatTellsTheGateway() async throws {
        let (model, _, _, http, server) = try await signedIn()
        defer {
            server.cancel()
            model.signOut()
        }
        model.visibleContactID = "scout"
        try await waitUntil { sessionRequests(http).contains("PATCH /api/sessions/stored-1") }
        let mark = try #require(http.requests.last { $0.httpMethod == "PATCH" }?.jsonBody)
        #expect(mark["expected_revision"] == 7)
        #expect(mark["profile"] == "scout")
    }
}
