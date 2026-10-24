import Foundation
import Testing

@testable import HermesKit

@MainActor
struct UsageTests {
    private func openThread() async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    private let usage: JSONValue = [
        "input": 120_000, "output": 8_000, "calls": 14, "compressions": 1,
        "context_used": 76_000, "context_max": 200_000, "context_percent": 38, "context_estimated": false,
    ]

    @Test func usageLoadsAndFollowsEveryReply() async throws {
        let (thread, gateway) = try await openThread()
        async let loaded: Void = thread.loadUsage()
        _ = try await gateway.answer(1, method: "session.usage", result: usage)
        await loaded
        #expect(thread.usage?.context == ChatUsage.Context(used: 76_000, max: 200_000, percent: 38, estimated: false))
        #expect(thread.usage?.input == 120_000)

        thread.apply(
            GatewayEvent(
                type: "message.complete", sessionID: "live-1", seq: nil,
                payload: ["text": "Done", "usage": ["context_used": 90_000, "context_max": 200_000, "context_percent": 45]]
            ))
        #expect(thread.usage?.context?.percent == 45)
    }

    @Test func noContextUntilTheGatewayKnowsIt() {
        #expect(ChatUsage(["calls": 0, "input": 0, "output": 0, "total": 0])?.context == nil)
        #expect(ChatUsage(nil) == nil)
    }

    @Test func compressingSaysWhatChangedAndKeepsTheTranscript() async throws {
        let (thread, gateway) = try await openThread()
        async let done: Void = thread.compress()
        let params = try await gateway.answer(
            1, method: "session.compress",
            result: [
                "status": "compressed", "removed": 40, "before_tokens": 152_000, "after_tokens": 18_400,
                "usage": ["context_used": 18_400, "context_max": 200_000, "context_percent": 9],
                "messages": .array([]),
            ])
        await done
        #expect(params == ["session_id": "live-1"])
        #expect(thread.usage?.context?.percent == 9)
        #expect(
            thread.state.items.map(\.content) == [
                .notice("Compressed the conversation from about 152k to 18.4k tokens.")
            ])
        #expect(!thread.isCompressing)
    }

    @Test func refusedCompressionSaysWhy() async throws {
        let (thread, gateway) = try await openThread()
        async let done: Void = thread.compress()
        _ = try await gateway.answer(1, method: "session.compress", error: (4009, "session busy"))
        await done
        #expect(thread.state.items.map(\.content) == [.notice("Couldn't compress: session busy")])
    }

    @Test func tokenCountsReadShort() {
        #expect(ChatThread.tokens(950) == "950")
        #expect(ChatThread.tokens(18_400) == "18.4k")
        #expect(ChatThread.tokens(200_000) == "200k")
        #expect(ChatThread.tokens(1_260_000) == "1.3M")
    }
}
