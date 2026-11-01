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
        #expect(model.room(for: room)?.state.items.count == 5)
        #expect(model.thread(for: try #require(contacts.first { $0.id == "atlas" })).state.items.count == 5)

        let ops = model.thread(for: try #require(contacts.first { $0.id == "ops" }))
        #expect(ops.secrets.count == 1)
        #expect(!ops.isLinkUnencrypted)
        let ledger = model.thread(for: try #require(contacts.first { $0.id == "ledger" }))
        #expect(ledger.secrets.first?.kind == .sudo(command: "sudo systemctl restart invoice-worker"))
        #expect(ledger.isLinkUnencrypted)
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
