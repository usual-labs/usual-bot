import Foundation
import Testing

@testable import HermesKit

/// A slow gateway answers one request at a time, so opening every chat at once left the last ones,
/// and the roster read behind them, past their timeout, and the dropped link opened them all again.
@MainActor
struct ChatOpeningTests {
    private func model(on gateway: ScriptedGateway) async -> AppModel {
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        model.channel = channel
        model.link = .online(.legacy)
        return model
    }

    private func agent(_ id: String) -> Contact {
        var contact = Contact(id: id, name: id.capitalized, details: AgentDetails(profile: id))
        contact.chatID = "chat-\(id)"
        return contact
    }

    private func resumes(_ gateway: ScriptedGateway) -> [JSONValue] {
        gateway.socket.sent.filter { $0["method"] == "session.resume" }
    }

    @Test func theChatOnScreenOpensWithOnlyAFewOthers() async throws {
        let gateway = ScriptedGateway()
        let model = await model(on: gateway)
        model.contacts = ["a", "b", "c", "d", "e"].map(agent)
        model.visibleContactID = "e"

        model.attachChats()

        let opening = model.threads.filter { $0.value.isOpening }.map(\.key)
        #expect(opening.count == 3)  // Of five: the one on screen and two more.
        #expect(opening.contains("e"))
        try await waitUntilOnMain { resumes(gateway).count == 3 }
    }

    @Test func anOpenThatEndsLetsTheNextChatStart() async throws {
        let gateway = ScriptedGateway()
        let model = await model(on: gateway)
        model.contacts = ["a", "b", "c", "d"].map(agent)

        model.attachChats()
        try await waitUntilOnMain { resumes(gateway).count == AppModel.backgroundOpens }
        let first = try #require(resumes(gateway).first)
        let reply: JSONValue = [
            "jsonrpc": "2.0", "id": first["id"] ?? .null,
            "result": ["session_id": "live-1", "running": false, "messages": []],
        ]
        gateway.socket.deliver(String(decoding: try JSONEncoder().encode(reply), as: UTF8.self))

        try await waitUntilOnMain { resumes(gateway).count == AppModel.backgroundOpens + 1 }
    }

    @Test func aRosterReadThatTimesOutOnAnOpenLinkKeepsIt() async throws {
        let gateway = ScriptedGateway()
        let model = await model(on: gateway)
        let channel = try #require(model.channel)

        try await model.refreshRosterKeepingLink(on: channel, timeout: .milliseconds(50))

        #expect(await channel.isOpen)
        #expect(!gateway.socket.isClosed)
    }

    @Test func aRosterReadOnAClosedLinkStillDropsIt() async throws {
        let gateway = ScriptedGateway()
        let model = await model(on: gateway)
        let channel = try #require(model.channel)
        await channel.close()

        await #expect(throws: GatewayError.self) {
            try await model.refreshRosterKeepingLink(on: channel, timeout: .milliseconds(50))
        }
    }
}
