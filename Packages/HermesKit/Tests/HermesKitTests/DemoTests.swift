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
        #expect(model.thread(for: try #require(contacts.first { $0.id == "atlas" })).state.items.count == 5)

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
