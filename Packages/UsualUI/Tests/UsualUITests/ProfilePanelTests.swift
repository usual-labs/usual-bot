import Foundation
import Testing

@testable import HermesKit
@testable import UsualUI

/// What the profile's model list offers, and which routines it shows as next up.
struct ProfilePanelTests {
    private let providers = [
        ModelProvider(slug: "openrouter", name: "OpenRouter", models: ["x-ai/grok-5", "deepseek/deepseek-v4"]),
        ModelProvider(slug: "anthropic", name: "Anthropic", models: ["claude-opus-5-5", "claude-sonnet-5-5"]),
    ]

    @Test func theChatsProviderComesFirstWithEveryModel() {
        let current = ChatModel(name: "claude-opus-5-5", provider: "anthropic")
        let groups = ModelChoices.groups(providers, current: current, query: "")
        #expect(groups.map(\.id) == ["anthropic", "openrouter"])
        #expect(groups[0].models == ["claude-opus-5-5", "claude-sonnet-5-5"])
    }

    @Test func aModelOutsideTheShortlistStillShows() {
        let current = ChatModel(name: "claude-haiku-5-5", provider: "anthropic")
        let groups = ModelChoices.groups(providers, current: current, query: "")
        #expect(groups[0].models.first == "claude-haiku-5-5")
    }

    @Test func searchMatchesEveryWordInTheModelOrItsProvider() {
        let current = ChatModel(name: "claude-opus-5-5", provider: "anthropic")
        #expect(ModelChoices.groups(providers, current: current, query: "GROK").map(\.models) == [["x-ai/grok-5"]])
        #expect(
            ModelChoices.groups(providers, current: current, query: "anthropic sonnet").map(\.models) == [
                ["claude-sonnet-5-5"]
            ])
        #expect(ModelChoices.groups(providers, current: current, query: "gpt").isEmpty)
    }

    @Test func nextUpIsTheSoonestSwitchedOnRoutines() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let routines = [
            Routine(id: "later", name: "Later", schedule: "", isOn: true, nextRun: now.addingTimeInterval(7200)),
            Routine(id: "off", name: "Off", schedule: "", isOn: false, nextRun: now.addingTimeInterval(60)),
            Routine(id: "soon", name: "Soon", schedule: "", isOn: true, nextRun: now.addingTimeInterval(600)),
            Routine(id: "done", name: "Done", schedule: "", isOn: true, isFinished: true, nextRun: now),
            Routine(id: "never", name: "Never", schedule: "", isOn: true),
            Routine(id: "last", name: "Last", schedule: "", isOn: true, nextRun: now.addingTimeInterval(9000)),
        ]
        #expect(NextRoutines.soonest(routines).map(\.id) == ["soon", "later"])
    }

    @Test func aRoutineDropsTheTagNamingItsOwnBot() {
        func title(_ name: String) -> String {
            Routine(id: name, name: name, schedule: "", isOn: true).title(in: "dr-eggbot")
        }
        #expect(title("[bot:dr-eggbot] cf-home-ip") == "cf-home-ip")
        #expect(title("[BOT:Dr-Eggbot]transcript-healthcheck") == "transcript-healthcheck")
        #expect(title("[bot:other] cf-home-ip") == "[bot:other] cf-home-ip")
        #expect(title("[bot:dr-eggbot]") == "[bot:dr-eggbot]")
        #expect(title("Morning brief [bot:dr-eggbot]") == "Morning brief [bot:dr-eggbot]")
    }

    @Test func compressTurnsProminentAtSeventyPercent() {
        func context(_ percent: Int) -> ChatUsage.Context {
            .init(used: percent * 2_000, max: 200_000, percent: percent, estimated: false)
        }
        #expect(!ContextGauge.isFilling(context(69)))
        #expect(ContextGauge.isFilling(context(70)))
    }
}
