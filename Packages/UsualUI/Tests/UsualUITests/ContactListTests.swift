import HermesKit
import Testing

@testable import UsualUI

struct ContactSearchTests {
    private let scout = Contact(id: "scout", name: "Scout", preview: "Found 4 mentions of the launch")

    @Test func matchesNameOrLastMessageIgnoringCase() {
        #expect(ContactList.matches(scout, "sco"))
        #expect(ContactList.matches(scout, "LAUNCH"))
        #expect(!ContactList.matches(scout, "writer"))
    }

    @Test func blankSearchShowsEveryone() {
        #expect(ContactList.matches(scout, ""))
        #expect(ContactList.matches(scout, "   "))
    }
}
