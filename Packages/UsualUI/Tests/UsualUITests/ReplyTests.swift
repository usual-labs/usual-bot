import Foundation
import Testing

@testable import UsualUI

struct ReplyTests {
    @Test func aReplyQuotesTheMessageBeforeYours() {
        let quote = QuotedMessage(author: "Atlas", text: "Turbopuffer fits best.\n\n- cheapest\n- fast")
        #expect(quote.excerpt == "Turbopuffer fits best. - cheapest - fast")
        #expect(
            quote.message("Start the trial") == "> Atlas: Turbopuffer fits best. - cheapest - fast\n\nStart the trial")
    }

    @Test func aRoomReplyMentionsTheAuthor() {
        let quote = QuotedMessage(author: "Shiv", text: "Accepted.", mention: "shiv")
        #expect(quote.message("Ship card 5") == "> Shiv: Accepted.\n\n@shiv Ship card 5")
    }

    @Test func longMessagesAreShortenedAndAttachmentLinesDropped() {
        let quote = QuotedMessage(author: "You", text: String(repeating: "a", count: 300) + "\n\n@image:/h/a.png")
        #expect(quote.excerpt == String(repeating: "a", count: 200) + "…")
    }

    @Test func selectedWordsAreQuotedWholeLineByLine() {
        let quote = QuotedMessage(author: "Scout", selection: "• daily drop\n\n  none of the four personas  ")
        #expect(quote.excerpt == "• daily drop none of the four personas")
        #expect(quote.message("Why?") == "> Scout: • daily drop\n> none of the four personas\n\nWhy?")
        // The bubble shows the quote on one line again.
        #expect(QuotedMessage.split(quote.message("Why?")).quote == "Scout: • daily drop none of the four personas")
        #expect(QuotedMessage.split(quote.message("Why?")).text == "Why?")
    }

    @Test func selectedWordsAreNotShortened() {
        let long = String(repeating: "a", count: 300)
        let quote = QuotedMessage(author: "Scout", selection: long, mention: "scout")
        #expect(quote.message("") == "> Scout: \(long)\n\n@scout")
    }

    @Test func sentRepliesSplitBackIntoQuoteAndText() {
        let sent = QuotedMessage.split("> Atlas: Turbopuffer fits best.\n\nStart the trial")
        #expect(sent.quote == "Atlas: Turbopuffer fits best.")
        #expect(sent.text == "Start the trial")
        #expect(QuotedMessage.split("No quote here").quote == nil)
    }
}
