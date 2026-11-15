import HermesKit
import Testing

@testable import UsualUI

struct ChatHistoryTests {
    private let all: Set<Contact.ID> = ["forge", "atlas", "ops"]

    private func visited(_ ids: [Contact.ID?]) -> ChatHistory {
        var history = ChatHistory()
        for id in ids { history.visit(id) }
        return history
    }

    @Test func backAndForwardRetraceTheChatsYouOpened() {
        var history = visited(["forge", "atlas", "ops"])
        #expect(history.goBack(among: all) == "atlas")
        #expect(history.goBack(among: all) == "forge")
        #expect(!history.canGoBack(among: all))
        #expect(history.goForward(among: all) == "atlas")
        #expect(history.goForward(among: all) == "ops")
        #expect(!history.canGoForward(among: all))
    }

    @Test func goingBackThenSelectingDropsWhatWasAhead() {
        var history = visited(["forge", "atlas", "ops"])
        _ = history.goBack(among: all)
        // The selection follows Back; the window reports it as a visit, which mustn't count.
        history.visit("atlas")
        #expect(history.canGoForward(among: all))
        history.visit("forge")
        #expect(!history.canGoForward(among: all))
        #expect(history.goBack(among: all) == "atlas")
    }

    @Test func deletedChatsAreSkipped() {
        var history = visited(["forge", "atlas", "ops"])
        #expect(history.goBack(among: ["forge", "ops"]) == "forge")
        #expect(!history.canGoBack(among: ["ops"]))
    }

    @Test func aChatOpenedAgainMovesToTheTop() {
        var history = visited(["forge", "atlas", "forge", "ops"])
        #expect(history.goBack(among: all) == "forge")
        #expect(history.goBack(among: all) == "atlas")
        #expect(history.goBack(among: all) == nil)
    }

    @Test func closingTheChatKeepsItToGoBackTo() {
        var history = visited(["forge", nil])
        #expect(history.goBack(among: all) == "forge")
    }

    @Test func historyKeepsTheLatestFifty() {
        let ids = (0..<80).map { "bot\($0)" }
        var history = visited(ids)
        let everyone = Set(ids)
        var steps = 0
        while history.goBack(among: everyone) != nil { steps += 1 }
        #expect(steps == ChatHistory.limit)
    }
}
