import Foundation
import Testing

@testable import UsualUI

struct LinkTests {
    private func links(_ text: AttributedString) -> [String] {
        text.runs[\.link].compactMap { $0.0?.absoluteString }
    }

    @Test func typedAddressesBecomeLinks() {
        let text = Links.detect(in: "this was a nice read today: https://seoskill.dev/blog/humanizer-skill")
        #expect(links(text) == ["https://seoskill.dev/blog/humanizer-skill"])
        #expect(links(Links.detect(in: "see www.example.com or mail ops@example.com")).count == 2)
    }

    @Test func fileNamesStayWords() {
        #expect(links(Links.detect(in: "I left topics.md and README.md alone")).isEmpty)
    }

    @Test func repliesLinkBareAddressesButNotCode() {
        let blocks = MarkdownBlock.parse(
            "Docs at https://hermes.example.com/docs and `https://hermes.example.com/raw`.")
        guard case .paragraph(let text) = blocks.first else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(links(text) == ["https://hermes.example.com/docs"])
    }

    @Test func markdownLinksKeepTheirTarget() {
        let blocks = MarkdownBlock.parse("See [the guide](https://hermes.example.com/guide).")
        guard case .paragraph(let text) = blocks.first else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(links(text) == ["https://hermes.example.com/guide"])
    }

    @Test func linksAreUnderlined() {
        let text = Links.detect(in: "https://hermes.example.com").underliningLinks()
        #expect(text.runs.allSatisfy { $0.underlineStyle == .single })
    }

    @Test func aMarkdownLinkCopiesItsTargetNotItsWords() {
        let blocks = MarkdownBlock.parse("See [the guide](https://hermes.example.com/guide?x=1#top) now.")
        #expect(Links.urls(in: blocks).map(\.absoluteString) == ["https://hermes.example.com/guide?x=1#top"])
    }

    @Test func linksComeInReadingOrderEachOnce() {
        let blocks = MarkdownBlock.parse(
            """
            Start at [one](https://a.example.com) or https://b.example.com, then [again](https://a.example.com).

            - A list item with www.c.example.com
            > A quote with [two](https://d.example.com)

            | Name | Where |
            | --- | --- |
            | Docs | [the table](https://e.example.com/limits) |
            """)
        #expect(
            Links.urls(in: blocks).map(\.absoluteString) == [
                "https://a.example.com", "https://b.example.com", "http://www.c.example.com",
                "https://d.example.com", "https://e.example.com/limits",
            ])
    }

    @Test func addressesInCodeAreNotLinks() {
        let blocks = MarkdownBlock.parse(
            "Run `curl https://raw.example.com`:\n\n```\ncurl https://code.example.com\n```")
        #expect(Links.urls(in: blocks).isEmpty)
    }

    @Test func aMessageYouTypedLinksItsBareAddresses() {
        #expect(
            Links.urls(inPlain: "docs https://docs.example.com/search and mail ops@example.com").map(\.absoluteString)
                == ["https://docs.example.com/search", "mailto:ops@example.com"])
    }

    @Test func aLinkAttributeNamesAnAddressWhetherURLOrString() {
        #expect(Links.url(from: URL(string: "https://hermes.example.com")) == URL(string: "https://hermes.example.com"))
        #expect(Links.url(from: "https://hermes.example.com/a") == URL(string: "https://hermes.example.com/a"))
        #expect(Links.url(from: nil) == nil)
        #expect(Links.url(from: 3) == nil)
    }

    @Test func onlyWebAndMailLinksOpen() throws {
        #expect(Links.isOpenable(try #require(URL(string: "https://hermes.example.com"))))
        #expect(Links.isOpenable(try #require(URL(string: "mailto:ops@example.com"))))
        // A path in a Markdown link names a file on the gateway.
        #expect(!Links.isOpenable(try #require(URL(string: "/home/agent/report.pdf"))))
        #expect(!Links.isOpenable(try #require(URL(string: "file:///Users/agent/report.pdf"))))
    }

    @Test func aMenuNamesALinkByItsHostAndPath() throws {
        #expect(
            Links.shortName(try #require(URL(string: "https://www.docs.example.com/search/limits")))
                == "docs.example.com/search/limits")
        #expect(Links.shortName(try #require(URL(string: "https://hermes.example.com/"))) == "hermes.example.com")
        #expect(Links.shortName(try #require(URL(string: "/home/agent/report.pdf"))) == "/home/agent/report.pdf")
        let long = try #require(URL(string: "https://hermes.example.com/" + String(repeating: "a", count: 80)))
        #expect(Links.shortName(long).count == 40)
    }
}
