import Foundation
import HermesKit
import JavaScriptCore
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

    // MARK: - Talking back

    /// Runs the page's `send` script in JavaScriptCore, with the app's channel and the page's
    /// click listener stood in for. `answer` is what the app replies with.
    private func page(canSend: Bool, answer: String = "{ok:true}") throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript(
            """
            var window = this, sent = [], listeners = {}, timers = 0;
            function setTimeout(f, ms) { timers++; return timers }
            function clearTimeout() {}
            function addEventListener(type, f) { listeners[type] = f }
            var webkit = {messageHandlers: {hermes: {postMessage: function(p) {
              sent.push(p); return Promise.resolve(\(answer)) }}}};
            """)
        context.evaluateScript(WidgetPage.sendScript(canSend: canSend))
        return context
    }

    @Test func sendHandsThePromptToTheAppAndResolvesWithItsAnswer() throws {
        let context = try page(canSend: true, answer: #"{ok:false,error:"undelivered",reason:"offline"}"#)
        context.evaluateScript(
            """
            var results = [];
            window.hermes.send("Refresh").then(function(a) { results.push(a.reason) });
            window.hermes.send("   ").then(function(a) { results.push(a.error) });
            window.hermes.send(42).then(function(a) { results.push(a.error) });
            """)
        #expect(context.evaluateScript("JSON.stringify(sent)").toString() == #"["Refresh"]"#)
        #expect(context.evaluateScript("JSON.stringify(results)").toString() == #"["invalid","invalid","offline"]"#)
        #expect(context.evaluateScript("window.hermes.maxLength").toInt32() == 500)
        #expect(context.evaluateScript("window.hermes.canSend").toBool())
    }

    @Test func aClickOnADataHermesSendElementSendsItsPrompt() throws {
        let context = try page(canSend: false)
        context.evaluateScript(
            """
            var button = {getAttribute: function(name) { return name === "data-hermes-send" ? "Check again" : null }};
            listeners.click({target: {closest: function(selector) { return selector === "[data-hermes-send]" ? button : null }}});
            listeners.click({target: {closest: function() { return null }}});
            """)
        #expect(context.evaluateScript("JSON.stringify(sent)").toString() == #"["Check again"]"#)
        #expect(!context.evaluateScript("window.hermes.canSend").toBool())
    }
}

struct WidgetLoadingTests {
    private func step(
        _ phase: InlineWidget.Phase, online: Bool = true, writing: Bool = false, runs: Bool = true, stale: Bool = false
    ) -> InlineWidget.LoadStep {
        InlineWidget.loadStep(phase, runs: runs, isBeingWritten: writing, isOnline: online, isStale: stale)
    }

    @Test func aFailedOrWaitingPageLoadsWhenTheGatewayIsBack() {
        #expect(step(.failed("Not connected"), online: false) == .waitForGateway)
        #expect(step(.failed("Not connected"), online: true) == .load)
        #expect(step(.offline, online: true) == .load)
        #expect(step(.loading, online: false) == .waitForGateway)
    }

    @Test func aPageAlreadyReadIsntReadAgain() {
        #expect(step(.loaded("<p>hi</p>"), online: true) == .keep)
        // Losing the gateway leaves a running page as it is.
        #expect(step(.loaded("<p>hi</p>"), online: false) == .keep)
    }

    @Test func aRunningPageIsReadAgainAfterATurnInItsChat() {
        #expect(step(.loaded("<p>hi</p>"), stale: true) == .load)
        // Offline the page stays as it is, and is read when a later turn ends.
        #expect(step(.loaded("<p>hi</p>"), online: false, stale: true) == .keep)
        #expect(step(.loaded("<p>hi</p>"), writing: true, stale: true) == .keep)
    }

    @Test func nothingLoadsWhileTheReplyIsWrittenOrWhereWidgetsDontRun() {
        #expect(step(.loading, writing: true) == .keep)
        #expect(step(.loading, runs: false) == .keep)
    }
}
