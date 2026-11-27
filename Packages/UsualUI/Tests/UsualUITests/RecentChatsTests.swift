import Testing

@testable import UsualUI

struct RecentChatsTests {
    @Test func keepsTheChatsShownLastAndLetsGoOfTheOldest() {
        var recent = RecentChats(limit: 3)
        for id in ["a", "b", "c"] { recent.use(id) }
        #expect(recent.ids == ["a", "b", "c"])
        recent.use("d")
        #expect(recent.ids == ["b", "c", "d"])
    }

    @Test func goingBackToAChatKeepsItsPlaceAndKeepsItLonger() {
        var recent = RecentChats(limit: 3)
        for id in ["a", "b", "c", "a"] { recent.use(id) }
        // Same order, so its view isn't moved; but "b" is now the oldest.
        #expect(recent.ids == ["a", "b", "c"])
        recent.use("d")
        #expect(recent.ids == ["a", "c", "d"])
    }

    @Test func showingAChatIncludesItBeforeItsUsed() {
        var recent = RecentChats(limit: 2)
        recent.use("a")
        recent.use("b")
        #expect(recent.showing("c") == ["b", "c"])
        #expect(recent.showing("a") == ["a", "b"])
        #expect(recent.ids == ["a", "b"])
    }

    @Test func keepsAtLeastTheChatShown() {
        var recent = RecentChats(limit: 0)
        recent.use("a")
        recent.use("b")
        #expect(recent.ids == ["b"])
    }
}
