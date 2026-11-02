import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// `GET /api/analytics/usage` as `hermes_cli/web_routers/analytics.py` (Hermes bf0203a794) answers it.
@MainActor
struct UsageOverviewTests {
    private nonisolated static let full = """
        {"daily":[\
        {"day":"2026-10-30","input_tokens":1200,"output_tokens":300,"cache_read_tokens":9000,\
        "reasoning_tokens":100,"estimated_cost":0.04,"actual_cost":0,"sessions":2,"api_calls":7},\
        {"day":"2026-11-01","input_tokens":800,"output_tokens":200,"cache_read_tokens":null,\
        "reasoning_tokens":null,"estimated_cost":0.01,"actual_cost":0,"sessions":1,"api_calls":3}],\
        "by_model":[{"model":"claude-sonnet-5-5","input_tokens":2000,"output_tokens":500,"estimated_cost":0.05,\
        "sessions":3,"api_calls":10}],\
        "by_task":[\
        {"task":"title_generation","input_tokens":40,"output_tokens":10,"estimated_cost":0.0,"api_calls":3,\
        "models":["gpt-mini"]},\
        {"task":"compression","input_tokens":600,"output_tokens":150,"estimated_cost":0.002,"api_calls":1,\
        "models":["gpt-mini"]}],\
        "totals":{"total_input":2000,"total_output":500,"total_cache_read":9000,"total_reasoning":100,\
        "total_estimated_cost":0.05,"total_actual_cost":0,"total_sessions":3,"total_api_calls":10},\
        "period_days":7,\
        "skills":{"summary":{"total_skill_loads":0,"total_skill_edits":0,"total_skill_actions":0,\
        "distinct_skills_used":0},"top_skills":[]},\
        "tools":[{"tool":"terminal","count":4,"percentage":100.0}]}
        """

    /// No sessions in the period: `SUM` gives `null`, `COUNT` 0, and nothing is listed.
    private nonisolated static let empty = """
        {"daily":[],"by_model":[],"by_task":[],"totals":{"total_input":null,"total_output":null,\
        "total_cache_read":null,"total_reasoning":null,"total_estimated_cost":0,"total_actual_cost":0,\
        "total_sessions":0,"total_api_calls":null},"period_days":7,\
        "skills":{"summary":{},"top_skills":[]},"tools":[]}
        """

    /// Before `by_task` (#23270), `tools`, and the cache and thinking columns.
    private nonisolated static let older = """
        {"daily":[{"day":"2026-11-01","input_tokens":500,"output_tokens":50,"estimated_cost":0,"sessions":1}],\
        "by_model":[],"totals":{"total_input":500,"total_output":50,"total_estimated_cost":0,\
        "total_actual_cost":0.12,"total_sessions":1},"period_days":30,"skills":{"summary":{},"top_skills":[]}}
        """

    private func parse(_ text: String) throws -> UsageReport {
        try UsageReport(json: JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), calendar: calendar)
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }()

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    @Test func readsTokensDaysBackgroundWorkAndCost() throws {
        let report = try parse(Self.full)
        #expect(report.main == UsageReport.Tokens(fresh: 2000, reused: 9000, written: 500, thinking: 100))
        #expect(report.days.map(\.date) == [day(10, 30), day(11, 1)])
        #expect(report.days[1].tokens == UsageReport.Tokens(fresh: 800, reused: 0, written: 200, thinking: 0))
        #expect(report.jobs.map(\.name) == ["compression", "title_generation"])
        #expect(report.jobs[0].tokens == 750)
        #expect(report.jobs[0].calls == 1)
        #expect(report.calls == 10)
        // Background work isn't in the sessions' counters, so it adds to them.
        #expect(report.totalTokens == 11_500 + 800)
        #expect(abs((report.cost?.amount ?? 0) - 0.052) < 1e-9)
        #expect(report.cost?.isEstimate == true)
    }

    @Test func nothingInThePeriodIsEmpty() throws {
        let report = try parse(Self.empty)
        #expect(report.isEmpty)
        #expect(report.cost == nil)
        #expect(report.days.isEmpty && report.jobs.isEmpty)
    }

    @Test func anOlderHermesWithoutBackgroundWorkOrCacheStillReads() throws {
        let report = try parse(Self.older)
        #expect(report.main == UsageReport.Tokens(fresh: 500, reused: 0, written: 50, thinking: 0))
        #expect(report.jobs.isEmpty)
        #expect(report.calls == 0)
        // The provider's own bill wins over an estimate.
        #expect(report.cost == UsageReport.Cost(amount: 0.12, isEstimate: false))
    }

    @Test func somethingElseIsntAReport() {
        #expect(throws: GatewayError.invalidResponse) { try parse(#"{"detail":"nope"}"#) }
        #expect(throws: GatewayError.invalidResponse) { try parse("[]") }
    }

    @Test func daysWithNothingAreFilledIn() throws {
        let report = try parse(Self.full)
        let week = report.daily(last: 7, until: day(11, 2).addingTimeInterval(3600 * 15), calendar: calendar)
        #expect(week.first?.date == day(10, 27))
        #expect(week.last?.date == day(11, 2))
        #expect(week.count == 7)
        #expect(week.filter { $0.tokens.total > 0 }.map(\.date) == [day(10, 30), day(11, 1)])
        // A listed day before the window's whole days (it starts part-way through one) stays.
        let short = report.daily(last: 2, until: day(11, 2), calendar: calendar)
        #expect(short.first?.date == day(10, 30))
    }

    @Test func combinesBotsByDayAndJob() throws {
        let both = UsageReport.combined([try parse(Self.full), try parse(Self.older)])
        #expect(both.main.fresh == 2500)
        #expect(both.days.count == 2)
        #expect(both.days[1].tokens.fresh == 1300)
        #expect(both.jobs.map(\.name) == ["compression", "title_generation"])
        #expect(abs((both.cost?.amount ?? 0) - 0.172) < 1e-9)
        #expect(both.cost?.isEstimate == true)
    }

    // MARK: - Across Bots

    private func overview(_ http: ScriptedHTTP, agents: [Contact]) -> UsageOverview {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        return UsageOverview(auth: { auth }, agents: { agents })
    }

    private func agent(_ id: String, profile: String? = nil) -> Contact {
        Contact(id: id, name: id.capitalized, details: profile.map { AgentDetails(profile: $0) })
    }

    @Test func asksEachBotsProfileForThePeriod() async throws {
        let http = ScriptedHTTP { request in
            request.url?.query?.contains("profile=ops%20team") == true ? (200, Self.full) : (200, Self.empty)
        }
        let usage = overview(http, agents: [agent("forge"), agent("ops", profile: "ops team")])
        usage.period = .month
        await usage.refresh()
        let queries = Set(http.requests.compactMap { $0.url?.query })
        #expect(queries == ["days=30&profile=forge", "days=30&profile=ops%20team"])
        #expect(http.requests.allSatisfy { $0.url?.path == "/api/analytics/usage" })
        #expect(usage.phase == .ready)
        // A Bot that used nothing isn't listed.
        #expect(usage.bots.map(\.id) == ["ops"])
        #expect(usage.combined.totalTokens == 12_300)
        // The other period hasn't loaded.
        usage.period = .week
        #expect(usage.phase == .loading)
    }

    @Test func anOlderGatewayWithoutTheRouteSaysSo() async {
        let usage = overview(
            ScriptedHTTP { _ in (404, #"{"detail":"No such API endpoint: /api/analytics/usage"}"#) },
            agents: [agent("forge"), agent("atlas")])
        await usage.refresh()
        #expect(usage.phase == .unsupported)
    }

    @Test func aBotThatFailsIsNamedAndTheRestShow() async {
        let http = ScriptedHTTP { request in
            request.url?.query?.contains("forge") == true
                ? (404, #"{"detail":"Profile 'forge' does not exist."}"#) : (200, Self.full)
        }
        let usage = overview(http, agents: [agent("forge"), agent("atlas")])
        await usage.refresh()
        #expect(usage.phase == .ready)
        #expect(usage.bots.map(\.id) == ["atlas"])
        #expect(usage.problems == ["Couldn't load Forge's usage: Profile 'forge' does not exist. (HTTP 404)"])
    }

    @Test func aFailedRefreshKeepsTheNumbersShown() async {
        let fail = Mutex(false)
        let http = ScriptedHTTP { _ in
            fail.withLock { $0 } ? (503, #"{"detail":"Session store is busy"}"#) : (200, Self.full)
        }
        let usage = overview(http, agents: [agent("atlas")])
        await usage.refresh()
        fail.withLock { $0 = true }
        await usage.refresh()
        #expect(usage.phase == .ready)
        #expect(usage.bots.count == 1)
        #expect(usage.problems == ["Couldn't refresh: Session store is busy (HTTP 503)"])
    }

    @Test func aFirstLoadThatFailsSaysWhy() async {
        let usage = overview(ScriptedHTTP { _ in (503, #"{"detail":"Session store is busy"}"#) }, agents: [agent("a")])
        await usage.refresh()
        #expect(usage.phase == .failed("Session store is busy (HTTP 503)"))
    }

    @Test func signingOutForgetsTheNumbers() async {
        let usage = overview(ScriptedHTTP { _ in (200, Self.full) }, agents: [agent("atlas")])
        await usage.refresh()
        usage.clear()
        #expect(usage.phase == .loading)
        #expect(usage.bots.isEmpty)
    }
}
