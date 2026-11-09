import Foundation
import Testing

@testable import HermesKit

@MainActor
struct DemoTests {
    @Test func demoShowsAgentsARoomAndAnApprovalWithoutAGateway() throws {
        let model = AppModel.demo()
        #expect(model.session == .signedIn(try GatewayAddress(parsing: "https://hermes.example.com")))
        let contacts = model.sidebarContacts
        #expect(contacts.filter { $0.kind == .agent }.count == 5)
        #expect(contacts.first { $0.id == "forge" }?.activity == .needsYou)

        let room = try #require(contacts.first { $0.kind != .agent })
        #expect(model.room(for: room)?.state.items.count == 6)
        let atlas = model.thread(for: try #require(contacts.first { $0.id == "atlas" }))
        #expect(atlas.state.items.count == 7)
        #expect(
            atlas.state.items[5].content
                == .result(
                    title: "From the routine “Competitor pricing watch”",
                    detail: "Northwind cut its Team plan from $12 to $10 a seat. The other two pages haven't changed."))

        let ops = model.thread(for: try #require(contacts.first { $0.id == "ops" }))
        #expect(!ops.isLinkUnencrypted)
        let ledger = model.thread(for: try #require(contacts.first { $0.id == "ledger" }))
        #expect(ledger.secrets.first?.kind == .sudo(command: "sudo systemctl restart invoice-worker"))
        #expect(ledger.secrets.count == 2)
        #expect(ledger.isLinkUnencrypted)
        let scribe = model.thread(for: try #require(contacts.first { $0.id == "scribe" }))
        #expect(scribe.questions.count == 1)
        #expect(scribe.connection != nil)
    }

    @Test func demoListMixesIdleUnreadWorkingAndNeedsYou() throws {
        let contacts = AppModel.demo().sidebarContacts
        let activity = Dictionary(uniqueKeysWithValues: contacts.map { ($0.name, $0.activity) })
        #expect(
            activity == [
                "Forge": .needsYou, "Atlas": .idle, "Scribe": .needsYou, "Ops": .working, "Ledger": .needsYou,
                "Launch crew": .idle,
            ])
        #expect(contacts.first { $0.id == "atlas" }?.unreadCount == 1)
        #expect(contacts.first { $0.id == "ops" }?.preview == "Find what's filling the disk on db-1.")
    }

    @Test func stoppingTheDemosRunningReplyEndsIt() throws {
        let model = AppModel.demo()
        let ops = model.thread(for: try #require(model.sidebarContacts.first { $0.id == "ops" }))
        ops.stop()
        #expect(!ops.state.isRunning)
        #expect(ops.state.items.last?.content == .notice("Stopped"))
    }

    /// New Room works in the demo, as renaming and deleting one do, instead of failing on the
    /// gateway it doesn't have.
    @Test func demoMakesARoomWithoutAGateway() async throws {
        let model = AppModel.demo()
        let agents = model.sidebarContacts.filter { $0.id == "forge" || $0.id == "ledger" }
        let id = try await model.createRoom(named: "Billing", agents: agents)
        let room = try #require(model.sidebarContacts.first { $0.id == id })
        #expect(room.name == "Billing")
        #expect(room.kind == .room(memberIDs: ["forge", "ledger"]))
        #expect(model.room(for: room)?.phase == .ready)
        // A second room gets its own ID.
        #expect(try await model.createRoom(named: "Billing", agents: agents) != id)
    }

    /// Push's switches and Send Test work in the demo, as if the gateway had taken them.
    @Test func demoPushMutesAndSendsATestWithoutAGateway() async throws {
        let model = AppModel.demo()
        let push = model.push
        #expect(push.isActive)
        try await push.setMuted("forge", true)
        try await push.sendTest()
        try await push.save(.init(previews: false))
    }

    @Test func demoShowsUsageForEveryBotThatAgreesAcrossPeriods() async {
        let model = AppModel.demo()
        await model.usage.refresh()
        #expect(model.usage.bots.map(\.id) == ["forge", "atlas", "ops", "scribe", "ledger"])
        let week = model.usage.combined.totalTokens
        #expect(model.usage.combined.cost != nil)
        model.usage.period = .month
        await model.usage.refresh()
        #expect(model.usage.combined.totalTokens > week)
    }

    @Test func opsReadsItsSummaryAsAVoiceMemoWithItsTranscript() throws {
        let model = AppModel.demo()
        let ops = model.thread(for: try #require(model.sidebarContacts.first { $0.id == "ops" }))
        let items = ops.state.items
        let reply = try #require(items.lastIndex { if case .assistant = $0.content { true } else { false } })
        #expect(
            SpokenAudio.transcripts(in: items, replyAt: reply, audioPaths: [DemoMedia.voiceMemoPath])
                == [DemoMedia.voiceMemoPath: DemoMedia.voiceMemoText])
        #expect(Set(model.media.demoMakers.keys) == [DemoMedia.voiceMemoPath, DemoMedia.clipPath])
    }

    @Test func demoShowsTheVaultAndItsPromptsWithFakeData() throws {
        let model = AppModel.demo()
        let ledger = try #require(model.sidebarContacts.first { $0.id == "ledger" })
        #expect(ledger.activity == .needsYou)
        let thread = model.thread(for: ledger)
        #expect(thread.vaultPrompts.count == 3)
        #expect(!thread.vaultAnswersAreUnencrypted)
        #expect(!thread.answer(thread.vaultPrompts[0], secret: "nothing connects here"))

        let vault = model.vault(for: ledger)
        #expect(vault.phase == .ready)
        #expect(vault.items.map(\.kind) == ["login", "login", "payment", "address"])
        #expect(vault.items.allSatisfy { ($0.origin ?? "example.com").contains("example.com") })
        #expect(vault.managers.count == 2)
    }
}
