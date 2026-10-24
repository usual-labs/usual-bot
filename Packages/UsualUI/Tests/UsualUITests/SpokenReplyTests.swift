import Testing

@testable import UsualUI

struct SpokenReplyTests {
    @Test func speaksSentencesAsTheyFinish() {
        var spoken = SpokenReply()
        #expect(spoken.sentences(in: "Turbopuffer fits best", final: false).isEmpty)
        #expect(
            spoken.sentences(in: "Turbopuffer fits best. It's the cheapest at our", final: false) == [
                "Turbopuffer fits best."
            ])
        #expect(
            spoken.sentences(in: "Turbopuffer fits best. It's the cheapest at our size.", final: true) == [
                "It's the cheapest at our size."
            ])
    }

    @Test func readsMarkdownAsWords() {
        var spoken = SpokenReply()
        let reply = """
            ## Plan
            - **pgvector** keeps everything in [Postgres](https://postgresql.org).
            See https://example.com/docs for more.

            """
        #expect(
            spoken.sentences(in: reply, final: true) == [
                "Plan", "pgvector keeps everything in Postgres.", "See a link for more.",
            ])
    }

    @Test func skipsCodeAndFileLines() {
        var spoken = SpokenReply()
        let reply = """
            Here's the fix.
            ```swift
            let x = 1. Not this.
            ```
            MEDIA:/home/h/chart.png
            Done.
            """
        #expect(spoken.sentences(in: reply, final: true) == ["Here's the fix.", "Done."])
    }
}
