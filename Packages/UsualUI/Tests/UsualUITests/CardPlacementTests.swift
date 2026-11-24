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

    /// Another Bot's message and what this Bot did for it fold into one row, and a card that came
    /// in during it shows after the whole exchange.
    @Test func anExchangeWithAnotherBotIsOneRowWithCardsAfterIt() {
        var items = items([0, 1, 2, 3, 4])
        items[1].content = .botMessage(from: "CMO", text: "Move the routines.", isNote: false)
        let exchanges = BotExchange.all(in: items)
        #expect(exchanges.map(\.items) == [1..<5])
        #expect(TranscriptView.rows(of: items, cardsAt: 5, folding: exchanges).map(\.id) == [0, 1, -1, -2])
        #expect(TranscriptView.rows(of: items, cardsAt: 3, folding: exchanges).map(\.id) == [0, 1, -1, -2])
        // A window starting inside it still shows it.
        #expect(TranscriptView.rows(of: items, cardsAt: 5, from: 3, folding: exchanges).map(\.id) == [1, -1, -2])
    }

    /// With tools hidden in Settings, the lines for tools go, and messages, routine results and
    /// another Bot's exchange stay.
    @Test func hidingToolsLeavesOnlyWhatWasSaid() {
        var items = items([0, 1, 2, 3, 4, 5, 6])
        items[1].content = .activity([])
        items[2].content = .progress(todos: [], helpers: [])
        items[3].content = .routine(name: "Inbox", output: "Nothing new.")
        items[5].content = .botMessage(from: "CMO", text: "Move the routines.", isNote: false)
        items[6].content = .activity([])
        let exchanges = BotExchange.all(in: items)
        #expect(TranscriptView.rows(of: items, cardsAt: 7, folding: exchanges).map(\.id) == [0, 1, 2, 3, 4, 5, -1, -2])
        #expect(
            TranscriptView.rows(of: items, cardsAt: 7, folding: exchanges, showingTools: false).map(\.id)
                == [0, 3, 4, 5, -1, -2])
    }

    /// Two replies with a hidden tool line between them read as one answer; shown, the line parts them.
    @Test func repliesJoinAcrossAHiddenToolLine() {
        var items = items([0, 1, 2, 3])
        items[1].content = .activity([])
        items[3].content = .activity([])
        let hidden = TranscriptView.joins(items, at: 2, dates: [:], showingTools: false, draftBelow: true)
        #expect(hidden.above && hidden.below)
        #expect(TranscriptView.joins(items, at: 0, dates: [:], showingTools: false, draftBelow: false).below)
        let shown = TranscriptView.joins(items, at: 2, dates: [:], showingTools: true, draftBelow: true)
        #expect(!shown.above && !shown.below)
        // A date above the second reply still parts them.
        #expect(!TranscriptView.joins(items, at: 2, dates: [2: "Today"], showingTools: false, draftBelow: false).above)
    }
}
