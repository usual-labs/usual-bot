import Foundation
import HermesKit
import Testing

@testable import UsualUI

@MainActor
struct WidgetTests {
    @Test func aPreviewLineIsAWidgetBetweenItsWords() {
        let blocks = MarkdownBlock.parse(
            """
            Disk use on db-1:
            ::preview{file="disk.html" height="320"}
            Tap a folder for its files.
            """)
        #expect(blocks.count == 3)
        #expect(blocks[1] == .widget(WidgetDirective(file: "disk.html", height: 320)))
    }

    @Test func aPreviewOfAFileThatIsntAPageShowsTheFile() {
        #expect(MarkdownBlock.parse(#"::preview{file="/tmp/chart.png"}"#) == [.media(path: "/tmp/chart.png")])
    }

    @Test func aPreviewLineInCodeIsCode() {
        let blocks = MarkdownBlock.parse("```\n::preview{file=\"disk.html\"}\n```")
        #expect(blocks == [.code(language: nil, #"::preview{file="disk.html"}"#)])
    }

    @Test func wordsLeaveTheWidgetOut() {
        let reply = "Here it is.\n::preview{file=\"disk.html\"}"
        #expect(SelectableText.plain(reply) == "Here it is.")
        #expect(QuotedMessage(author: "Ops", text: reply).excerpt == "Here it is.")
        var spoken = SpokenReply()
        #expect(spoken.sentences(in: reply, final: true) == ["Here it is."])
        #expect(!SpokenReply.hasWords(in: #"::preview{file="disk.html"}"#))
    }

    @Test func theFrameStartsAtTheAttributeWithinLimits() {
        #expect(WidgetPage.startHeight(nil) == 280)
        #expect(WidgetPage.startHeight(480) == 480)
        #expect(WidgetPage.startHeight(20) == 120)
        #expect(WidgetPage.startHeight(9000) == 1200)
    }

    @Test func sizeReportsAreCheckedBeforeTheyMoveAnything() {
        #expect(WidgetPage.size(from: ["height": 312.4, "width": 280]) ?? (0, 0) == (312, 280))
        #expect(WidgetPage.size(from: ["height": 200]) ?? (0, 0) == (200, 0))
        #expect(WidgetPage.size(from: ["height": -5, "width": 10]) == nil)
        #expect(WidgetPage.size(from: ["height": Double.infinity]) == nil)
        #expect(WidgetPage.size(from: "200") == nil)
    }

    @Test func theThemeUsesHermessNamesAndComesFirst() {
        let theme = WidgetPage.Theme(
            dark: true, foreground: WidgetPage.css(red: 1, green: 1, blue: 1),
            mutedForeground: WidgetPage.css(red: 0.5, green: 0.5, blue: 0.5, opacity: 0.5), accent: "red",
            border: "gray", card: "black", fontSize: 15)
        #expect(theme.css.hasPrefix(":root{color-scheme:dark;--foreground:rgb(255 255 255);"))
        #expect(theme.css.contains("--muted-foreground:rgb(128 128 128 / 0.5);--accent:red;--border:gray;--card:black"))
        #expect(theme.css.contains("background:transparent"))
        #expect(theme.css.contains("font:15.0px -apple-system"))
        // Inserted before the page's own markup, so the page's styles win.
        #expect(WidgetPage.themeScript(theme).contains("insertBefore(s,d.firstChild)"))
    }
}
