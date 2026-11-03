import Testing

@testable import UsualUI

struct SelectTextTests {
    @Test func aReplyBecomesTheWordsItShows() {
        let reply = """
            ## Plan

            **Turbopuffer** fits best: see [the docs](https://example.com).

            - Index nightly
            - Fall back after 300 ms

            ```sh
            make index
            ```
            MEDIA:/tmp/chart.png
            """
        #expect(
            SelectableText.plain(reply)
                == "Plan\n\nTurbopuffer fits best: see the docs.\n\n• Index nightly\n• Fall back after 300 ms\n\nmake index"
        )
    }

    @Test func plainTextStaysAsItIs() {
        #expect(SelectableText.plain("Yes, keep the old search.") == "Yes, keep the old search.")
        #expect(SelectableText.plain("MEDIA:/tmp/a.ogg").isEmpty)
    }
}
