import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// Subscription limits as `hermes_cli/inventory.py::_apply_usage` (Hermes 2bd378ed1b) puts them
/// on `model.options` provider rows.
@MainActor
struct PlanLimitTests {
    private static let anthropicRow: JSONValue = [
        "slug": "anthropic", "name": "Anthropic", "models": ["claude-opus-5-5", "claude-sonnet-5-5"],
        "usage": [
            "windows": [
                [
                    "label": "Current session", "used_percent": 6.0,
                    "resets_at": "2026-11-20T02:59:59.584112+00:00", "scope": "account",
                ],
                [
                    "label": "Current week", "used_percent": 92.0, "resets_at": "2026-11-24T06:59:59+00:00",
                    "scope": "account",
                ],
                ["label": "Opus week", "used_percent": 97.0, "resets_at": .null, "scope": "model"],
            ]
        ],
    ]

    @Test func rowsCarryTheirLimits() throws {
        let provider = try #require(ModelProvider(row: Self.anthropicRow))
        #expect(provider.limits.map(\.label) == ["Current session", "Current week", "Opus week"])
        #expect(provider.limits[0].resetsAt == Date(timeIntervalSince1970: 1_795_143_599))
        #expect(provider.limits[1].resetsAt == Date(timeIntervalSince1970: 1_795_503_599))
        #expect(provider.limits[2].resetsAt == nil)
        #expect(provider.limits[2].scope == .model)
        #expect(provider.limits.map(\.name) == ["5-hour", "weekly", "weekly Opus"])
    }

    @Test func rowsWithoutNumbersHaveNoLimits() throws {
        let apiKey = try #require(ModelProvider(row: ["slug": "openai", "models": ["gpt-5.5"]]))
        #expect(apiKey.limits.isEmpty)
        // Several logins report each one apart; the app shows none of them.
        let pooled = try #require(
            ModelProvider(row: ["slug": "openai", "models": ["gpt-5.5"], "usage": ["windows": [], "accounts": []]]))
        #expect(pooled.limits.isEmpty)
    }

    @Test func aModelLimitWarnsOnlyForItsModels() throws {
        let provider = try #require(ModelProvider(row: Self.anthropicRow))
        let opus = try #require(PlanLimitWarning(provider: provider, model: "claude-opus-5-5"))
        #expect(opus.limit.label == "Opus week")
        let sonnet = try #require(PlanLimitWarning(provider: provider, model: "claude-sonnet-5-5"))
        #expect(sonnet.limit.label == "Current week")
        #expect(sonnet.provider == "Anthropic")
    }

    @Test func noWarningBelowNinetyPercent() {
        let provider = ModelProvider(
            slug: "anthropic", name: "Anthropic", models: ["claude-sonnet-5-5"],
            limits: [PlanLimit(label: "Current week", usedPercent: 89.9)])
        #expect(PlanLimitWarning(provider: provider, model: "claude-sonnet-5-5") == nil)
    }

    @Test func aDismissedWarningComesBackAtTheNextBandOrReset() {
        func key(_ percent: Double, reset: TimeInterval = 100) -> String? {
            let provider = ModelProvider(
                slug: "anthropic", name: "Anthropic", models: ["m"],
                limits: [
                    PlanLimit(
                        label: "Current week", usedPercent: percent, resetsAt: Date(timeIntervalSince1970: reset))
                ])
            return PlanLimitWarning(provider: provider, model: "m")?.dismissKey
        }
        #expect(key(90) == key(94.9))
        #expect(key(90) != key(95))
        #expect(key(95) != key(100))
        #expect(key(91) != key(91, reset: 200))
    }

    // MARK: - Every Bot's limits

    private func contact(_ id: String) -> Contact {
        Contact(id: id, name: id.capitalized, details: AgentDetails(profile: id))
    }

    private func plan(_ percent: Double, slug: String = "anthropic", model: String = "claude-sonnet-5-5")
        -> PlanLimitOverview.BotPlan
    {
        PlanLimitOverview.BotPlan(
            provider: ModelProvider(
                slug: slug, name: slug.capitalized, models: [model],
                limits: percent < 0 ? [] : [PlanLimit(label: "Current week", usedPercent: percent)]),
            model: model)
    }

    @Test func botsOnOneLoginShareAnAccount() async {
        let bots = ["forge", "atlas", "ops", "ledger"].map(contact)
        let plans = ["forge": plan(91), "atlas": plan(91), "ops": plan(40, slug: "openai"), "ledger": plan(-1)]
        let overview = PlanLimitOverview(agents: { bots }, retryAfter: .zero) { plans[$0] }
        await overview.refresh()
        #expect(overview.accounts.map { $0.bots.map(\.id) } == [["forge", "atlas"], ["ops"]])
    }

    /// Hermes reads each profile's numbers at its own moment, so Bots on one login can report
    /// 10.2% and 10.4%, or reset times seconds apart. They're still one login.
    @Test func botsOnOneLoginShareAnAccountWhenTheirNumbersWereReadApart() async {
        let reset = Date(timeIntervalSince1970: 1_795_503_599)
        func reading(_ percent: Double, resetsIn offset: TimeInterval, slug: String = "anthropic")
            -> PlanLimitOverview.BotPlan
        {
            PlanLimitOverview.BotPlan(
                provider: ModelProvider(
                    slug: slug, name: slug.capitalized, models: ["m"],
                    limits: [
                        PlanLimit(label: "Current session", usedPercent: percent / 2),
                        PlanLimit(label: "Current week", usedPercent: percent, resetsAt: reset + offset),
                    ]),
                model: "m")
        }
        let bots = ["forge", "atlas", "ops", "other"].map(contact)
        let plans = [
            "forge": reading(10.2, resetsIn: 0), "atlas": reading(10.4, resetsIn: 3),
            "ops": reading(10.2, resetsIn: 0, slug: "openai"),
            // Another login's week ends at another hour.
            "other": reading(10.2, resetsIn: 6 * 3600),
        ]
        let overview = PlanLimitOverview(agents: { bots }, retryAfter: .zero) { plans[$0] }
        await overview.refresh()
        let accounts = overview.accounts
        #expect(accounts.map { $0.bots.map(\.id) } == [["forge", "atlas"], ["ops"], ["other"]])
        // The higher reading is the newer one: use only grows until the limit resets.
        #expect(accounts.first?.provider.limits.map(\.usedPercent) == [5.2, 10.4])
    }

    @Test func aRoomWarnsForTheMembersItStops() async {
        let bots = ["forge", "atlas", "ops"].map(contact)
        let plans = ["forge": plan(96), "atlas": plan(96), "ops": plan(10, slug: "openai")]
        let overview = PlanLimitOverview(agents: { bots }, retryAfter: .zero) { plans[$0] }
        await overview.refresh(bots)
        let warning = overview.warning(for: bots)
        #expect(warning?.members.map(\.id) == ["forge", "atlas"])
        #expect(warning?.warning.limit.usedPercent == 96)
        #expect(overview.warning(for: [bots[2]]) == nil)
    }

    @Test func aBotWithoutNumbersYetIsAskedOnceMore() async {
        let bots = [contact("forge")]
        let calls = Mutex(0)
        let overview = PlanLimitOverview(agents: { bots }, retryAfter: .zero) { _ in
            // Hermes fetches the numbers in the background the first time it's asked.
            let call = calls.withLock { count in
                count += 1
                return count
            }
            return self.plan(call == 1 ? -1 : 50)
        }
        await overview.refresh()
        #expect(calls.withLock { $0 } == 2)
        #expect(overview.accounts.first?.provider.limits.first?.usedPercent == 50)
        // Fresh numbers aren't asked for again.
        await overview.refresh()
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func theBotsPlanIsItsCurrentProvider() {
        let result: JSONValue = [
            "provider": "anthropic", "model": "claude-opus-5-5",
            "providers": [["slug": "openai", "models": ["gpt-5.5"]], Self.anthropicRow],
        ]
        let plan = PlanLimitOverview.plan(from: result)
        #expect(plan?.provider.slug == "anthropic")
        #expect(plan?.model == "claude-opus-5-5")
        #expect(PlanLimitOverview.plan(from: ["providers": []]) == nil)
    }
}
