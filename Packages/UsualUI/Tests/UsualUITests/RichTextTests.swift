#if os(macOS)
    import AppKit
    import Testing

    @testable import UsualUI

    @MainActor
    struct RichTextTests {
        private let reply = """
            ## Plan

            **Turbopuffer** fits best: see https://hermes.example.com.

            - Index nightly
            - Fall back after 300 ms

            > Keep the old search
            """

        @Test func aReplyIsOneTextAcrossItsBlocks() {
            let text = RichText.reply(MarkdownBlock.parse(reply), size: 15)
            #expect(
                RichText.plain(text.string)
                    == "Plan\nTurbopuffer fits best: see https://hermes.example.com.\n• Index nightly\n• Fall back after 300 ms\nKeep the old search"
            )
            let link = text.attribute(.link, at: (text.string as NSString).range(of: "https://").location, effectiveRange: nil)
            #expect((link as? URL)?.host == "hermes.example.com")
        }

        @Test func selectingAcrossBlocksCopiesTheWordsAsTheyRead() {
            let view = SelectableTextView()
            view.show(.reply(MarkdownBlock.parse(reply), size: 15))
            let start = (view.string as NSString).range(of: "best").location
            let end = (view.string as NSString).range(of: "nightly")
            view.setSelectedRange(NSRange(location: start, length: NSMaxRange(end) - start))
            #expect(view.selectedWords == "best: see https://hermes.example.com.\n• Index nightly")
        }

        @Test func aShortMessageIsAsWideAsItsWords() {
            let view = SelectableTextView()
            view.show(.mine("Hi", size: 15))
            let short = view.fittingSize(width: 560)
            #expect(short.width < 40)
            view.show(.mine(String(repeating: "word ", count: 200), size: 15))
            let long = view.fittingSize(width: 560)
            #expect(long.width <= 560)
            #expect(long.height > short.height * 5)
        }
    }
#endif
