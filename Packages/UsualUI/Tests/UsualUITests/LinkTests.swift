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
        let blocks = MarkdownBlock.parse("Docs at https://hermes.example.com/docs and `https://hermes.example.com/raw`.")
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
}
