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

    @Test func eachQuoteCarriesYourReplyUnderIt() {
        var quotes: [QuotedMessage] = []
        quotes.add(QuotedMessage(author: "Atlas", selection: "cheapest\nfast", note: " Check egress too "))
        quotes.add(QuotedMessage(author: "Atlas", selection: "Pinecone costs 3×"))
        quotes.add(QuotedMessage(author: "You", selection: "which index?", note: "Still open"))
        let sent = quotes.message("Start the trial")
        #expect(
            sent
                == "> Atlas: cheapest\n> fast\n\nCheck egress too\n\n> Atlas: Pinecone costs 3×\n\n"
                + "> You: which index?\n\nStill open\n\nStart the trial")
        #expect(
            QuotedMessage.parts(sent) == [
                .quote("Atlas: cheapest fast"), .text("Check egress too"), .quote("Atlas: Pinecone costs 3×"),
                .quote("You: which index?"), .text("Still open\n\nStart the trial"),
            ])
        // Previews and notifications read your words, one after another.
        #expect(QuotedMessage.split(sent).text == "Check egress too\n\nStill open\n\nStart the trial")
        // A reply alone, with nothing typed in the box.
        #expect(
            [QuotedMessage(author: "Atlas", selection: "fast", note: "Why?")].message("") == "> Atlas: fast\n\nWhy?")
    }

    @Test func repliesUnderQuotesAreEnoughToSend() {
        // Your answers to the quotes are a message, with nothing typed in the box.
        #expect([QuotedMessage(author: "Atlas", selection: "fast", note: "yes")].hasReplies)
        // A quote alone isn't: there's nothing of yours to send yet.
        #expect(![QuotedMessage(author: "Atlas", selection: "fast", note: "  ")].hasReplies)
        #expect(![QuotedMessage]().hasReplies)
    }

    @Test func quotingTheSameWordsAgainKeepsTheNewerReply() {
        var quotes = [QuotedMessage(author: "Atlas", selection: "fast", note: "Why?")]
        quotes.add(QuotedMessage(author: "Atlas", selection: "fast"))
        #expect(quotes.map(\.note) == ["Why?"])
        quotes.add(QuotedMessage(author: "Atlas", selection: "fast", note: "How fast?"))
        #expect(quotes.map(\.note) == ["How fast?"])
    }

    @Test func aRoomReplyAddressesTheAuthorAfterTheReplies() {
        let quotes = [QuotedMessage(author: "Shiv", selection: "Accepted.", mention: "shiv", note: "Thanks")]
        #expect(quotes.message("Next card") == "> Shiv: Accepted.\n\nThanks\n\n@shiv Next card")
    }

    @Test func onlyAMessageThatStartsWithAQuoteHasQuotes() {
        // Your own Markdown quote, with no author, stays your words.
        #expect(QuotedMessage.parts("> just a thought\n\nok") == [.text("> just a thought\n\nok")])
        #expect(QuotedMessage.parts("Look:\n\n> Atlas: fast") == [.text("Look:\n\n> Atlas: fast")])
        // A quote of yours inside a reply, with no blank line before it, isn't a new one.
        #expect(
            QuotedMessage.parts("> Atlas: fast\n\nAs they said\n> Ref: x") == [
                .quote("Atlas: fast"), .text("As they said\n> Ref: x"),
            ])
        #expect(QuotedMessage.parts("").isEmpty)
    }
}
