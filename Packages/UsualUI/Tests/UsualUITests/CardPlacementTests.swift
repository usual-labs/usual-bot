import Testing

@testable import HermesKit
@testable import UsualUI

struct CardPlacementTests {
    private func items(_ ids: [Int]) -> [TranscriptItem] {
        ids.map { TranscriptItem(id: $0, content: .assistant("\($0)")) }
    }

    @Test func cardsWithNothingAfterThemSitAtTheEndUnderTheReplyBeingWritten() {
        let items = items([0, 1, 2])
        #expect(TranscriptView.cardsIndex(in: items, after: nil) == 3)
        #expect(TranscriptView.cardsIndex(in: items, after: 2) == 3)
        #expect(TranscriptView.rows(of: items, cardsAt: 3).map(\.id) == [0, 1, 2, -1, -2])
    }

    @Test func aMessageSentWhileACardWaitsComesAfterIt() {
        // The card came after item 1; you wrote 2 and the agent answered 3.
        let items = items([0, 1, 2, 3])
        let split = TranscriptView.cardsIndex(in: items, after: 1)
        #expect(split == 2)
        #expect(TranscriptView.rows(of: items, cardsAt: split).map(\.id) == [0, 1, -2, 2, 3, -1])
    }

    @Test func cardsKeepTheirPlaceWhenTheMessageBeforeThemGoes() {
        // Undo took back items 1 and 2; an item inserted earlier keeps a newer ID.
        #expect(TranscriptView.cardsIndex(in: items([0, 3]), after: 1) == 1)
        #expect(TranscriptView.cardsIndex(in: items([0, 7, 1, 2]), after: 1) == 3)
        #expect(TranscriptView.cardsIndex(in: items([4, 5]), after: 1) == 0)
        #expect(TranscriptView.cardsIndex(in: items([0, 1]), after: -1) == 0)
    }
}
