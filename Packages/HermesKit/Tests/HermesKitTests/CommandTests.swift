import Foundation
import Synchronization
import Testing

@testable import HermesKit

struct CommandCatalogTests {
    @Test func menuOffersSkillsUserCommandsAndChatBuiltins() {
        let catalog: JSONValue = [
            "pairs": [
                ["/help", "Show help"], ["/model", "Switch model"], ["/retry", "Retry the last message"],
                ["/deploy", "Quick: deploy staging"], ["/web-research", "Search the web"],
            ],
            "commands": ["/help": [:], "/model": [:], "/retry": [:]],
            "skills": ["/web-research": ["usage": 4, "origin": "bundled"]],
        ]
        #expect(
            ChatThread.commands(in: catalog) == [
                SlashCommand(name: "/retry", description: "Retry the last message", kind: .command),
                SlashCommand(name: "/deploy", description: "Quick: deploy staging", kind: .command),
                SlashCommand(name: "/web-research", description: "Search the web", kind: .skill),
            ])
    }
}

@MainActor
struct CommandRunTests {
    private func openThread() async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "hermes", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }
        thread.commands = [
            SlashCommand(name: "/web-research", description: "", kind: .skill),
            SlashCommand(name: "/deploy", description: "", kind: .command),
            SlashCommand(name: "/retry", description: "", kind: .command),
        ]
        return (thread, gateway)
    }

    @Test func aSkillSendsItsMessageButShowsWhatYouTyped() async throws {
        let (thread, gateway) = try await openThread()
        thread.send("/web-research pricing for Qdrant")
        let dispatch = try await gateway.answer(
            1, method: "command.dispatch",
            result: [
                "type": "skill", "message": "[Skill: web-research] …full instructions… pricing for Qdrant",
                "display": "/web-research pricing for Qdrant",
            ])
        #expect(dispatch == ["session_id": "live-1", "name": "web-research", "arg": "pricing for Qdrant"])
        let submit = try await gateway.answer(2, method: "prompt.submit", result: ["status": "streaming"])
        #expect(submit["text"] == "[Skill: web-research] …full instructions… pricing for Qdrant")
        #expect(thread.state.items.map(\.content) == [.user("/web-research pricing for Qdrant")])
        #expect(thread.state.isRunning)
    }

    @Test func commandOutputShowsWithoutATurn() async throws {
        let (thread, gateway) = try await openThread()
        thread.send("/deploy")
        _ = try await gateway.answer(
            1, method: "command.dispatch", result: ["type": "exec", "output": "Deployed 4f2a1c"])
        try await waitUntilOnMain { thread.state.items.count == 2 }
        #expect(thread.state.items.map(\.content) == [.user("/deploy"), .notice("Deployed 4f2a1c")])
        #expect(!thread.state.isRunning)
    }

    @Test func retryPutsTheMessageBackToEdit() async throws {
        let (thread, gateway) = try await openThread()
        thread.send("/retry")
        _ = try await gateway.answer(1, method: "command.dispatch", result: ["type": "prefill", "message": "Ship it"])
        try await waitUntilOnMain { thread.prefill == "Ship it" }
    }

    @Test func unknownSlashWordsAreOrdinaryMessages() async throws {
        let (thread, gateway) = try await openThread()
        thread.send("/shrug that's all")
        let submit = try await gateway.answer(1, method: "prompt.submit", result: ["status": "streaming"])
        #expect(submit["text"] == "/shrug that's all")
    }

    @Test func refusedCommandSaysWhy() async throws {
        let (thread, gateway) = try await openThread()
        thread.send("/deploy")
        _ = try await gateway.answer(1, method: "command.dispatch", error: (4018, "quick command failed"))
        try await waitUntilOnMain { !thread.state.items.isEmpty }
        #expect(thread.state.items.map(\.content) == [.notice("/deploy didn't run: quick command failed")])
    }
}

@MainActor
struct SkillListTests {
    private func list(_ http: ScriptedHTTP) -> SkillList {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        return SkillList(profile: "ops", auth: { auth })
    }

    @Test func loadsMostUsedFirstAndSwitchesThroughTheDashboard() async throws {
        let http = ScriptedHTTP { request in
            if request.httpMethod == "PUT" { return (200, #"{"ok":true,"name":"backups","enabled":false}"#) }
            return (
                200,
                #"[{"name":"backups","description":"Check backups","category":"ops","enabled":true,"usage":3,"provenance":"agent"},"#
                    + #"{"name":"web-research","description":"Search","category":null,"enabled":true,"usage":9,"provenance":"bundled"}]"#
            )
        }
        let skills = list(http)
        await skills.refresh()
        #expect(skills.skills.map(\.name) == ["web-research", "backups"])
        #expect(http.requests.first?.url?.query == "profile=ops")

        skills.setEnabled(false, for: skills.skills[1])
        #expect(skills.skills[1].enabled == false)
        try await waitUntil { http.requests.count == 2 }
        let toggle = try #require(http.requests.last)
        #expect(toggle.httpMethod == "PUT")
        #expect(toggle.url?.path == "/api/skills/toggle")
        #expect(toggle.jsonBody == ["name": "backups", "enabled": false, "profile": "ops"])
    }

    @Test func refusedSwitchMovesBack() async throws {
        let http = ScriptedHTTP { request in
            if request.httpMethod == "PUT" { return (500, #"{"detail":"config is read-only"}"#) }
            return (200, #"[{"name":"backups","description":"Check backups","enabled":true}]"#)
        }
        let skills = list(http)
        await skills.refresh()
        skills.setEnabled(false, for: skills.skills[0])
        try await waitUntilOnMain { skills.problem != nil }
        #expect(skills.skills[0].enabled)
        #expect(skills.problem == "Couldn't turn off “backups”: config is read-only (HTTP 500)")
    }
}
