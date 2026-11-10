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

    @Test func readsATableAsItsCells() {
        var spoken = SpokenReply()
        let reply = """
            | Store | Cost |
            |:------|-----:|
            | pgvector | Free |
            """
        #expect(spoken.sentences(in: reply, final: true) == ["Store, Cost", "pgvector, Free"])
    }

    @Test func readsAFilePathAsItsName() {
        #expect(
            SpokenReply.plain("Saved to `/Users/me/.hermes/out/report.pdf` and ~/notes/today.md.")
                == "Saved to report.pdf and today.md.")
        // Not paths: a fraction, either/or, a slash command.
        #expect(SpokenReply.plain("Use 1/2 cup and/or /help") == "Use 1/2 cup and/or /help")
    }

    @Test func knowsWhenThereIsNothingToRead() {
        #expect(SpokenReply.hasWords(in: "Here you go.\nMEDIA:/tmp/a.mp3"))
        #expect(!SpokenReply.hasWords(in: "MEDIA:/tmp/a.mp3\n[[audio_as_voice]]"))
        #expect(!SpokenReply.hasWords(in: "```\nlet x = 1\n```\n---"))
        #expect(!SpokenReply.hasWords(in: ""))
    }
}
