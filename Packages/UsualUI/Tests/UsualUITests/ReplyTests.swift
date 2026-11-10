import Testing

@testable import UsualUI

@MainActor
struct ReplyTests {
    @Test func aReplyQuotesTheMessageBeforeYours() {
        let quote = QuotedMessage(author: "Atlas", text: "Turbopuffer fits best.\n\n- cheapest\n- fast")
        #expect(quote.excerpt == "Turbopuffer fits best. - cheapest - fast")
        #expect(
            [quote].message("Start the trial")
                == "> Atlas: Turbopuffer fits best. - cheapest - fast\n\nStart the trial")
    }

    @Test func aRoomReplyAddressesTheQuotedAgent() {
        let quote = QuotedMessage(author: "Shiv", text: "Accepted.", mention: "shiv")
        #expect([quote].message("Ship card 5") == "> Shiv: Accepted.\n\n@shiv Ship card 5")
    }

    @Test func longQuotesAreCutAndAttachmentsLeftOut() {
        let quote = QuotedMessage(author: "You", text: String(repeating: "a", count: 300) + "\n\n@image:/h/a.png")
        #expect(quote.excerpt == String(repeating: "a", count: 200) + "…")
    }

    @Test func selectedWordsAreQuotedWholeLineByLine() {
        let quote = QuotedMessage(author: "Scout", selection: "• daily drop\n\n  none of the four personas  ")
        #expect(quote.excerpt == "• daily drop none of the four personas")
        #expect([quote].message("Why?") == "> Scout: • daily drop\n> none of the four personas\n\nWhy?")
        // The bubble shows the quote on one line again.
        let sent = QuotedMessage.split([quote].message("Why?"))
        #expect(sent.quotes == ["Scout: • daily drop none of the four personas"])
        #expect(sent.text == "Why?")
    }

    @Test func aLongSelectionIsSentWhole() {
        let long = String(repeating: "word ", count: 80).trimmingCharacters(in: .whitespaces)
        let quote = QuotedMessage(author: "Scout", selection: long, mention: "scout")
        #expect([quote].message("") == "> Scout: \(long)\n\n@scout")
    }

    @Test func sentRepliesSplitBackIntoQuoteAndText() {
        let sent = QuotedMessage.split("> Atlas: Turbopuffer fits best.\n\nStart the trial")
        #expect(sent.quotes == ["Atlas: Turbopuffer fits best."])
        #expect(sent.text == "Start the trial")
        #expect(QuotedMessage.split("No quote here").quotes.isEmpty)
        #expect(QuotedMessage.split("No quote here").text == "No quote here")
    }

    @Test func severalQuotesGoInFrontEachItsOwn() {
        var quotes: [QuotedMessage] = []
        quotes.add(QuotedMessage(author: "Atlas", selection: "cheapest\nfast"))
        quotes.add(QuotedMessage(author: "You", selection: "which one?"))
        // The same words again are still one quote.
        quotes.add(QuotedMessage(author: "You", selection: "which one?"))
        #expect(quotes.count == 2)

        let sent = quotes.message("Go with the first")
        #expect(sent == "> Atlas: cheapest\n> fast\n\n> You: which one?\n\nGo with the first")
        let split = QuotedMessage.split(sent)
        #expect(split.quotes == ["Atlas: cheapest fast", "You: which one?"])
        #expect(split.text == "Go with the first")
        #expect([QuotedMessage]().message("No quotes") == "No quotes")
    }

    @Test func aRoomMessageAddressesEachQuotedAgentOnce() {
        let quotes = [
            QuotedMessage(author: "Shiv", selection: "Accepted.", mention: "shiv"),
            QuotedMessage(author: "Scout", selection: "Blocked on card 4.", mention: "scout"),
            QuotedMessage(author: "Shiv", selection: "Card 5 next.", mention: "shiv"),
        ]
        #expect(
            quotes.message("Sort it out")
                == "> Shiv: Accepted.\n\n> Scout: Blocked on card 4.\n\n> Shiv: Card 5 next.\n\n@shiv @scout Sort it out"
        )
    }
}
