import Testing

@testable import HermesKit
@testable import UsualUI

struct TranscriptWindowTests {
    private func items(_ ids: some Sequence<Int>) -> [TranscriptItem] {
        ids.map { TranscriptItem(id: $0, content: .assistant("\($0)")) }
    }

    @Test func aLongConversationOpensOnItsNewestPage() {
        let items = items(0..<100)
        var window = TranscriptWindow()
        window.reset(items)
        #expect(window.start(in: items) == 100 - TranscriptWindow.first)
        #expect(window.start(in: self.items(0..<10)) == 0)
    }

    @Test func newMessagesDontPushTheTopOnesOut() {
        var window = TranscriptWindow()
        window.reset(items(0..<100))
        #expect(window.start(in: items(0..<130)) == 100 - TranscriptWindow.first)
    }

    @Test func scrollingUpAddsPagesUntilTheFirstMessage() {
        let page = TranscriptWindow.page
        let items = items(0..<(TranscriptWindow.first + page + 10))
        var window = TranscriptWindow()
        window.reset(items)
        #expect(window.start(in: items) == page + 10)
        #expect(window.showEarlier(in: items) == true)
        #expect(window.start(in: items) == 10)
        #expect(window.showEarlier(in: items) == true)
        #expect(window.start(in: items) == 0)
        #expect(window.showEarlier(in: items) == false)
    }

    @Test func aMessageASearchJumpedToStaysShown() {
        let items = items(0..<100)
        var window = TranscriptWindow()
        window.reset(items)
        #expect(window.start(in: items, including: 12) == 12)
        #expect(window.showEarlier(in: items, including: 12) == true)
        #expect(window.start(in: items, including: 12) == 0)
    }

    @Test func undoingTheFirstMessageShownStartsAtTheNextOne() {
        var window = TranscriptWindow()
        window.reset(items(0..<(TranscriptWindow.first + 10)))
        #expect(window.start(in: items(Array(0..<10) + [11, 12])) == 10)
    }

    @Test func rowsBeforeTheStartAreLeftOutButTheCardsStay() {
        let items = items(0..<5)
        #expect(TranscriptView.rows(of: items, cardsAt: 5, from: 3).map(\.id) == [3, 4, -1, -2])
        // Cards that came after an item no longer shown still show.
        #expect(TranscriptView.rows(of: items, cardsAt: 1, from: 3).map(\.id) == [-2, 3, 4, -1])
    }
}
