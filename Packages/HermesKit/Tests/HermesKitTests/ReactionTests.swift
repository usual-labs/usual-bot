import Foundation
import Testing

@testable import HermesKit

struct ReactionRuleTests {
    private let agentHeart = Reaction(emoji: "❤️", byAgent: true)

    @Test func oneReactionPerAuthorLikeTapback() {
        let mine = Reaction(emoji: "👍", byAgent: false)
        #expect(Reaction.toggling("👍", in: [agentHeart]) == [agentHeart, mine])
        #expect(Reaction.toggling("👍", in: [agentHeart, mine]) == [agentHeart])
        #expect(Reaction.toggling("🎉", in: [mine]) == [Reaction(emoji: "🎉", byAgent: false)])
        #expect(Reaction.toggling(nil, in: [mine, agentHeart]) == [agentHeart])
    }

    @Test func historyCarriesRowsAndReactions() throws {
        let messages: JSONValue = [
            ["role": "user", "text": "Ship it", "row_id": 41],
            [
                "role": "assistant", "text": "Shipped.", "row_id": 42,
                "display_metadata": ["reactions": [["emoji": "🎉", "author": "user", "at": 1_792_700_000]]],
            ],
        ]
        let state = ThreadState(history: try messages.decode([HistoryMessage].self), running: false)
        #expect(state.items.map(\.rowID) == [41, 42])
        #expect(state.items[1].reactions == [Reaction(emoji: "🎉", byAgent: false)])
    }

    @Test func cachedItemsFromBeforeReactionsStillLoad() throws {
        let old = Data(#"{"id":3,"content":{"assistant":{"_0":"Hi"}}}"#.utf8)
        let item = try JSONDecoder().decode(TranscriptItem.self, from: old)
        #expect(item.content == .assistant("Hi"))
        #expect(item.rowID == nil)
        #expect(item.reactions.isEmpty)
    }
}

@MainActor
struct ReactTests {
    private func openThread(messages: JSONValue) async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": messages])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    @Test func reactingAddressesTheStoredRow() async throws {
        let (thread, gateway) = try await openThread(messages: [
            ["role": "user", "text": "Ship it", "row_id": 41], ["role": "assistant", "text": "Shipped.", "row_id": 42],
        ])
        let reply = thread.state.items[1]
        thread.react("🎉", to: reply)
        #expect(thread.state.items[1].reactions == [Reaction(emoji: "🎉", byAgent: false)])

        let params = try await gateway.answer(
            1, method: "message.react", result: ["row_id": 42, "reactions": [["emoji": "🎉", "author": "user"]]])
        #expect(params == ["session_id": "live-1", "row_id": 42, "emoji": "🎉", "author": "user"])
    }

    @Test func aLiveReplyIsTheNewestOfItsRole() async throws {
        let (thread, gateway) = try await openThread(messages: [["role": "assistant", "text": "Hello", "row_id": 7]])
        thread.apply(GatewayEvent(type: "message.complete", sessionID: "live-1", seq: nil, payload: ["text": "Again"]))
        let live = try #require(thread.state.items.last)
        #expect(live.rowID == nil)
        #expect(thread.canReact(to: live))
        #expect(!thread.canReact(to: TranscriptItem(id: 99, content: .assistant("old"))))

        thread.react("👍", to: live)
        let params = try await gateway.answer(
            1, method: "message.react", result: ["row_id": 8, "reactions": [["emoji": "👍", "author": "user"]]])
        #expect(params["newest_role"] == "assistant")
        #expect(params["row_id"] == nil)
        try await waitUntilOnMain { thread.state.items.last?.rowID == 8 }
    }

    @Test func refusedReactionIsTakenBack() async throws {
        let (thread, gateway) = try await openThread(messages: [["role": "assistant", "text": "Hello", "row_id": 7]])
        thread.react("❤️", to: thread.state.items[0])
        _ = try await gateway.answer(1, method: "message.react", error: (4040, "message not found in this session"))
        try await waitUntilOnMain { thread.state.items[0].reactions.isEmpty }
        #expect(thread.state.items.last?.content == .notice("Couldn't react: message not found in this session"))
    }
}
