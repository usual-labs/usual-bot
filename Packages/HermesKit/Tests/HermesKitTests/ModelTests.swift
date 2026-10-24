import Foundation
import Testing

@testable import HermesKit

struct ModelCatalogTests {
    @Test func providersOfferTheirShortlistAndSayWhichModelsThink() {
        let row: JSONValue = [
            "slug": "openrouter", "name": "OpenRouter",
            "models": ["a/one", "a/two", "b/three"], "featured_models": ["a/two", "b/three"],
            "capabilities": ["a/two": ["reasoning": true], "b/three": ["reasoning": false]],
        ]
        let provider = ModelProvider(row: row)
        #expect(provider?.models == ["a/two", "b/three"])
        #expect(provider?.reasons("a/two") == true)
        #expect(provider?.reasons("b/three") == false)
        // Hermes assumes a model thinks when its catalog is silent.
        #expect(provider?.reasons("unlisted") == true)
    }

    @Test func olderGatewaysListModelsAsObjects() {
        let provider = ModelProvider(row: ["slug": "anthropic", "models": [["id": "claude-opus-5-5"]]])
        #expect(provider?.name == "anthropic")
        #expect(provider?.models == ["claude-opus-5-5"])
        #expect(ModelProvider(row: ["slug": "empty", "models": []]) == nil)
    }

    @Test func infoReadsModelAndReasoning() {
        let info: JSONValue = ["model": "gpt-5.5", "provider": "openai", "reasoning_effort": "high"]
        #expect(ChatModel(info: info) == ChatModel(name: "gpt-5.5", provider: "openai", reasoning: .high))
        // "" is the provider's default; "none" is thinking off.
        #expect(ChatModel(info: ["model": "m", "reasoning_effort": ""])?.reasoning == nil)
        #expect(ChatModel(info: ["model": "m", "reasoning_effort": "none"])?.reasoning == .off)
        #expect(ChatModel(info: ["provider": "openai"]) == nil)
    }
}

@MainActor
struct ModelSwitchTests {
    private func openThread() async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume",
            result: [
                "session_id": "live-1", "running": false, "messages": .array([]),
                "info": ["model": "claude-opus-5-5", "provider": "anthropic", "reasoning_effort": "medium"],
            ])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    @Test func resumeSaysWhichModelTheChatUses() async throws {
        let (thread, _) = try await openThread()
        #expect(thread.model == ChatModel(name: "claude-opus-5-5", provider: "anthropic", reasoning: .medium))
    }

    @Test func switchingAsksForThisChatOnly() async throws {
        let (thread, gateway) = try await openThread()
        async let outcome = thread.setModel("gpt-5.5", provider: "openai")
        let params = try await gateway.answer(
            1, method: "config.set", result: ["key": "model", "value": "gpt-5.5", "scope": "session"])
        #expect(params == ["session_id": "live-1", "key": "model", "value": "gpt-5.5 --provider openai --session"])
        #expect(await outcome == .switched)
        #expect(thread.model == ChatModel(name: "gpt-5.5", provider: "openai", reasoning: .medium))
    }

    @Test func anExpensiveModelNeedsAYesFirst() async throws {
        let (thread, gateway) = try await openThread()
        async let first = thread.setModel("o9-pro", provider: "openai")
        _ = try await gateway.answer(
            1, method: "config.set", result: ["confirm_required": true, "confirm_message": "o9-pro is $$$"])
        #expect(await first == .needsConfirmation("o9-pro is $$$"))
        #expect(thread.model?.name == "claude-opus-5-5")

        async let second = thread.setModel("o9-pro", provider: "openai", confirmed: true)
        let params = try await gateway.answer(2, method: "config.set", result: ["value": "o9-pro"])
        #expect(params["confirm_expensive_model"] == true)
        #expect(await second == .switched)
    }

    @Test func aSwitchDuringAReplyWaitsForTheNextMessage() async throws {
        let (thread, gateway) = try await openThread()
        async let outcome = thread.setModel("gpt-5.5", provider: "openai")
        _ = try await gateway.answer(1, method: "config.set", result: ["value": "gpt-5.5", "deferred": true])
        #expect(await outcome == .next)
        #expect(thread.state.items.map(\.content) == [.notice("gpt-5.5 takes over from your next message.")])
    }

    @Test func sessionInfoKeepsTheModelCurrent() async throws {
        let (thread, _) = try await openThread()
        thread.apply(
            GatewayEvent(
                type: "session.info", sessionID: "live-1", seq: nil,
                payload: ["model": "gpt-5.5", "provider": "openai", "reasoning_effort": "none"]))
        #expect(thread.model == ChatModel(name: "gpt-5.5", provider: "openai", reasoning: .off))
        #expect(thread.state.items.isEmpty)
    }

    @Test func refusedReasoningLevelGoesBack() async throws {
        let (thread, gateway) = try await openThread()
        thread.setReasoning(.high)
        #expect(thread.model?.reasoning == .high)
        let params = try await gateway.answer(1, method: "config.set", error: (4002, "unknown reasoning value"))
        #expect(params == ["session_id": "live-1", "key": "reasoning", "value": "high"])
        try await waitUntilOnMain { thread.model?.reasoning == .medium }
        #expect(thread.state.items.map(\.content) == [.notice("Couldn't change thinking: unknown reasoning value")])
    }

    @Test func modelsLoadFromTheCatalog() async throws {
        let (thread, gateway) = try await openThread()
        async let loaded: Void = thread.loadModels()
        _ = try await gateway.answer(
            1, method: "model.options",
            result: ["providers": [["slug": "openai", "name": "OpenAI", "models": ["gpt-5.5"]]]])
        await loaded
        #expect(thread.modelProviders.map(\.slug) == ["openai"])
    }
}
