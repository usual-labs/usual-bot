import Testing

@testable import HermesKit

struct WidgetDirectiveTests {
    @Test func readsTheFileAndStartingHeight() {
        #expect(
            WidgetDirective.parse(#"  ::preview{file="charts/cpu.html" height="480"}  "#)
                == WidgetDirective(file: "charts/cpu.html", height: 480))
        #expect(WidgetDirective.parse("::preview{file='a b.html'}") == WidgetDirective(file: "a b.html"))
        #expect(
            WidgetDirective.parse("::preview{#main .wide file=/tmp/x.html}") == WidgetDirective(file: "/tmp/x.html"))
        #expect(WidgetDirective.parse(#"::preview{file="x.html" height="tall"}"#)?.height == nil)
    }

    @Test func otherLinesAreNotWidgets() {
        #expect(WidgetDirective.parse(#"See ::preview{file="x.html"}"#) == nil)
        #expect(WidgetDirective.parse(#"::preview{file="x.html""#) == nil)
        #expect(WidgetDirective.parse(#"::preview{height="300"}"#) == nil)
        #expect(WidgetDirective.parse(#"::chart{file="x.html"}"#) == nil)
    }

    @Test func onlyPagesRun() {
        #expect(WidgetDirective(file: "/a/Chart.HTML").isPage)
        #expect(WidgetDirective(file: "a.htm").isPage)
        #expect(!WidgetDirective(file: "a.png").isPage)
        #expect(!WidgetDirective(file: "a.html.txt").isPage)
    }

    @Test func plainTextLeavesTheWidgetOut() {
        let reply = """
            Here's CPU overnight.
            ::preview{file="cpu.html"}
            """
        #expect(AgentAlert.plain(reply) == "Here's CPU overnight.")
        #expect(AgentAlert.plain(#"::preview{file="cpu.html"}"#) == "Sent a widget")
        #expect(MessageSearch.plain(reply) == "Here's CPU overnight.")
        #expect(RoomThread.readable(#"::preview{file="cpu.html"}"#) == "Sent a widget")
        #expect(RoomThread.readable("MEDIA:/a.pdf") == "Sent a file")
    }

    @Test func sidebarPreviewsLeaveTheWidgetOutEvenCutShort() {
        #expect(Contact.plainPreview(#"::preview{file="/home/hermes/work/cpu-overnig"#) == "Sent a widget")
        #expect(Contact.plainPreview(#"Here's CPU. ::preview{file="cpu.html"}"#) == "Here's CPU.")
        #expect(Contact.plainPreview("") == "")
    }
}
