import Foundation
import Testing

@testable import HermesKit

struct ContactRosterOrderTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func pinnedContactsComeFirst() {
        let recent = Contact(id: "recent", name: "Recent", lastActive: now)
        let pinned = Contact(id: "pinned", name: "Pinned", lastActive: now.addingTimeInterval(-3600), isPinned: true)

        #expect([recent, pinned].sorted(by: Contact.rosterOrder).map(\.id) == ["pinned", "recent"])
    }

    @Test func mostRecentlyActiveComesFirst() {
        let older = Contact(id: "older", name: "Older", lastActive: now.addingTimeInterval(-60))
        let newer = Contact(id: "newer", name: "Newer", lastActive: now)

        #expect([older, newer].sorted(by: Contact.rosterOrder).map(\.id) == ["newer", "older"])
    }

    @Test func neverActiveSortsLastThenByName() {
        let active = Contact(id: "active", name: "Zed", lastActive: now)
        let beta = Contact(id: "beta", name: "beta")
        let alpha = Contact(id: "alpha", name: "Alpha")

        #expect([beta, active, alpha].sorted(by: Contact.rosterOrder).map(\.id) == ["active", "alpha", "beta"])
    }
}
