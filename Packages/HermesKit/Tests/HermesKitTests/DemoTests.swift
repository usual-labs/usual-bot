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
    }
}
