import Foundation
import Testing

@testable import HermesKit

struct UsualPluginTests {
    private func channel(_ gateway: ScriptedGateway) async -> JSONRPCChannel {
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        return channel
    }

    @Test func installingGoesIntoEachBotAndTakesOutThePluginsItReplaces() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let restart = UsualPlugin.install(profiles: ["default", "ops"], on: channel)

        var index = 0
        for profile in ["default", "ops"] {
            let install = try await gateway.answer(
                index, method: "plugins.manage",
                result: ["ok": true, "plugin_name": "usual-bot", "restart_required": .bool(profile == "ops")])
            #expect(install["action"] == "install")
            #expect(install["identifier"] == "usual-labs/usual-bot#Integrations/usual-bot")
            #expect(install["profile"] == .string(profile))
            // The user said yes to Hermes's "caution" scan before this ran.
            #expect(install["force"] == true)
            #expect(install["enable"] == true)
            let push = try await gateway.answer(
                index + 1, method: "plugins.manage", error: (5026, "plugin 'usual-push' not found"))
            #expect(push == ["action": "remove", "name": "usual-push", "profile": .string(profile)])
            let browser = try await gateway.answer(index + 2, method: "plugins.manage", result: ["ok": true])
            #expect(browser["name"] == "usual-browser")
            index += 3
        }
        #expect(try await restart)
    }

    @Test func aRefusedInstallStopsAndSaysWhy() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        let install = Task { try await UsualPlugin.install(profiles: ["default", "ops"], on: channel) }

        _ = try await gateway.answer(0, method: "plugins.manage", error: (5026, "Security scan blocked plugin install"))
        await #expect(throws: GatewayError.self) { try await install.value }
        // Nothing more once it threw: not the old plugins' removal, nor the next Bot.
        #expect(gateway.socket.sent.count == 1)
    }

    @Test func aChatTellsThePluginItsStoredSessionWhenItOpens() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let opened = BotChat.open(profile: "shiv", knownID: "stored-9", on: channel)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "session_key": "stored-9", "running": false])
        #expect(try await opened.storedID == "stored-9")

        async let canonical = BotChat.open(profile: "shiv", knownID: "stored-9", on: channel)
        _ = try await gateway.answer(
            1, method: "session.resume",
            result: ["session_id": "stored-9", "stored_session_id": "stored-9", "running": false])
        #expect(try await canonical.storedID == "stored-9")
    }

    @MainActor
    @Test func openingAChatHandsItsStoredSessionToThePlugin() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        var noted: [String] = []
        thread.chatOpened = { noted.append($0) }
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume",
            result: ["session_id": "live-1", "session_key": "stored-1", "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }
        #expect(noted == ["stored-1"])
    }
}
