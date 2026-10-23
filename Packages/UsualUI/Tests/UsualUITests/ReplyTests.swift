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

    @Test func sentRepliesSplitBackIntoQuoteAndText() {
        let sent = QuotedMessage.split("> Atlas: Turbopuffer fits best.\n\nStart the trial")
        #expect(sent.quote == "Atlas: Turbopuffer fits best.")
        #expect(sent.text == "Start the trial")
        #expect(QuotedMessage.split("No quote here").quote == nil)
    }
}
