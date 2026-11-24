import Foundation
import Testing

@testable import HermesKit
@testable import UsualUI

struct PlanLimitNoticeTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    private func warning(_ percent: Double, resetsIn seconds: TimeInterval?) throws -> PlanLimitWarning {
        let provider = ModelProvider(
            slug: "anthropic", name: "Anthropic", models: ["claude-sonnet-5-5"],
            limits: [
                PlanLimit(label: "Current week", usedPercent: percent, resetsAt: seconds.map { now + $0 })
            ])
        return try #require(PlanLimitWarning(provider: provider, model: "claude-sonnet-5-5"))
    }

    @Test func aChatSaysHowMuchIsUsedAndWhenItResets() throws {
        let text = try warning(91.7, resetsIn: 3 * 86_400).chatText(agentName: "Forge", now: now)
        #expect(text.hasPrefix("You've used 91% of Anthropic's weekly limit. It resets "))
        // Never "100%" while some is left.
        #expect(
            try warning(99.9, resetsIn: nil).chatText(agentName: "Forge", now: now)
                == "You've used 99% of Anthropic's weekly limit.")
    }

    @Test func aUsedUpLimitSaysWhatToDo() throws {
        #expect(
            try warning(100, resetsIn: nil).chatText(agentName: "Forge", now: now)
                == "Anthropic's weekly limit is used up. Switch Forge to another model to keep going.")
        #expect(
            try warning(100, resetsIn: 600).chatText(agentName: "Forge", now: now).contains("Forge can reply again at ")
        )
    }

    @Test func aRoomNamesTheMembersItStops() throws {
        #expect(
            try warning(100, resetsIn: nil).roomText(members: ["Forge", "Atlas"], now: now)
                == "Anthropic's weekly limit is used up, so Forge and Atlas can't reply.")
        #expect(
            try warning(92, resetsIn: nil).roomText(members: ["Forge", "Atlas"], now: now)
                == "You've used 92% of Anthropic's weekly limit, which Forge and Atlas run on.")
        #expect(
            try warning(92, resetsIn: nil).roomText(members: ["Forge"], now: now)
                == "You've used 92% of Anthropic's weekly limit, which Forge runs on.")
    }

    @Test func dismissingKeepsOnlyRecentKeys() {
        var list = ""
        for index in 0..<25 { list = PlanLimitNotice.adding("k\(index)", to: list) }
        let keys = list.split(separator: "\n")
        #expect(keys.count == 20)
        #expect(keys.last == "k24")
    }
}
