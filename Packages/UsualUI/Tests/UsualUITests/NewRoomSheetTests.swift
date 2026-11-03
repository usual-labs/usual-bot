import Testing

@testable import UsualUI

@MainActor
struct NewRoomSheetTests {
    @Test func namesARoomFromItsAgentsInTheOrderPicked() {
        #expect(NewRoomSheet.suggestedName(for: []) == "")
        #expect(NewRoomSheet.suggestedName(for: ["Forge"]) == "Forge")
        #expect(NewRoomSheet.suggestedName(for: ["Forge", "Atlas"]) == "Forge & Atlas")
        #expect(NewRoomSheet.suggestedName(for: ["Forge", "Atlas", "Scribe"]) == "Forge, Atlas & Scribe")
    }

    @Test func saysWhyCreateIsOff() {
        #expect(NewRoomSheet.seatsNote(picked: 0, available: 5) == "Pick two to six agents.")
        #expect(NewRoomSheet.seatsNote(picked: 1, available: 5) == "Pick one more agent.")
        #expect(NewRoomSheet.seatsNote(picked: 2, available: 5) == nil)
        #expect(
            NewRoomSheet.seatsNote(picked: 0, available: 1)
                == "A room needs at least two agents, and this gateway has one. Make another with New Bot first.")
    }
}
