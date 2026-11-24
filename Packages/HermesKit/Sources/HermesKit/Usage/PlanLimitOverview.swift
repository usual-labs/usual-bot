import Foundation
import Observation

/// Each Bot's subscription limits, for Settings › Usage and for rooms: the limits of the provider
/// its default model runs on, from one `model.options` per profile. A chat reads its own catalog
/// instead (`ChatThread.planLimitWarning`), since a chat can run on another model than the Bot's.
@MainActor
@Observable
public final class PlanLimitOverview {
    /// What a Bot runs on by default, and that provider's limits.
    public struct BotPlan: Equatable, Sendable {
        public let provider: ModelProvider
        public let model: String?
    }

    /// One login's limits, and the Bots that use it. Hermes doesn't say which login a profile uses,
    /// so Bots on the same provider whose limits reset together are taken to share one.
    public struct Account: Identifiable, Equatable, Sendable {
        public let provider: ModelProvider
        public let bots: [Contact]
        public var id: String { ([provider.slug] + bots.map(\.id)).joined(separator: "|") }
    }

    /// A warning in a room: the fullest limit any member is near, and the members it stops.
    public struct RoomWarning: Equatable, Sendable {
        public let warning: PlanLimitWarning
        public let members: [Contact]
    }

    private(set) var plans: [String: BotPlan] = [:]
    private var loadedAt: [String: Date] = [:]
    private var loading: Set<String> = []

    @ObservationIgnored private let agents: @MainActor () -> [Contact]
    @ObservationIgnored private let fetch: @MainActor (_ profile: String) async throws -> BotPlan?
    @ObservationIgnored private let now: @MainActor () -> Date
    /// How long to wait before asking again for a Bot the gateway had no numbers for yet.
    @ObservationIgnored private let retryAfter: Duration

    init(
        agents: @escaping @MainActor () -> [Contact], now: @escaping @MainActor () -> Date = { .now },
        retryAfter: Duration = .seconds(10),
        fetch: @escaping @MainActor (_ profile: String) async throws -> BotPlan?
    ) {
        self.agents = agents
        self.now = now
        self.retryAfter = retryAfter
        self.fetch = fetch
    }

    convenience init(
        channel: @escaping @MainActor () -> JSONRPCChannel?, agents: @escaping @MainActor () -> [Contact]
    ) {
        self.init(agents: agents) { profile in
            guard let channel = channel() else { throw GatewayError.disconnected }
            let result = try await channel.call(
                "model.options", params: ["profile": .string(profile)], timeout: .seconds(20))
            return Self.plan(from: result)
        }
    }

    /// The Bot's current provider row from a `model.options` answer.
    nonisolated static func plan(from result: JSONValue) -> BotPlan? {
        guard let slug = result["provider"]?.stringValue, case .array(let rows) = result["providers"],
            let provider = rows.compactMap(ModelProvider.init(row:)).first(where: { $0.slug == slug })
        else { return nil }
        return BotPlan(provider: provider, model: result["model"]?.stringValue)
    }

    /// Logins with limits, the fullest first.
    public var accounts: [Account] {
        var groups: [(provider: ModelProvider, bots: [Contact])] = []
        for bot in agents() {
            guard let plan = plans[Self.profile(of: bot)], !plan.provider.limits.isEmpty else { continue }
            if let index = groups.firstIndex(where: { Self.sameLogin($0.provider, plan.provider) }) {
                groups[index].provider = Self.newer(groups[index].provider, plan.provider)
                groups[index].bots.append(bot)
            } else {
                groups.append((plan.provider, [bot]))
            }
        }
        func fullest(_ provider: ModelProvider) -> Double { provider.limits.map(\.usedPercent).max() ?? 0 }
        return groups.map { Account(provider: $0.provider, bots: $0.bots) }
            .sorted { fullest($0.provider) > fullest($1.provider) }
    }

    /// Whether two Bots' readings come from one login. Each profile's numbers are read at their own
    /// moment, so the percentages and reset times of one login drift apart a little; another
    /// login's limits reset at another time.
    nonisolated static func sameLogin(_ a: ModelProvider, _ b: ModelProvider) -> Bool {
        guard a.slug == b.slug, a.limits.map(\.label) == b.limits.map(\.label) else { return false }
        return zip(a.limits, b.limits).allSatisfy { a, b in
            // A limit with no reset time yet (no session running) says nothing either way.
            guard let first = a.resetsAt, let second = b.resetsAt else { return true }
            return abs(first.timeIntervalSince(second)) <= 10 * 60
        }
    }

    /// One login's limits from two readings: the higher of each, since use only grows until a
    /// limit resets.
    nonisolated static func newer(_ a: ModelProvider, _ b: ModelProvider) -> ModelProvider {
        let limits = zip(a.limits, b.limits).map { a, b in a.usedPercent >= b.usedPercent ? a : b }
        return ModelProvider(
            slug: a.slug, name: a.name, models: a.models, withoutReasoning: a.withoutReasoning, limits: limits)
    }

    /// The fullest limit near or past its end among `members`, with every member it stops.
    public func warning(for members: [Contact]) -> RoomWarning? {
        let warned = members.compactMap { member -> (Contact, PlanLimitWarning)? in
            guard let plan = plans[Self.profile(of: member)],
                let warning = PlanLimitWarning(provider: plan.provider, model: plan.model)
            else { return nil }
            return (member, warning)
        }
        guard let worst = warned.max(by: { $0.1.limit.usedPercent < $1.1.limit.usedPercent })?.1 else { return nil }
        return RoomWarning(warning: worst, members: warned.filter { $0.1.dismissKey == worst.dismissKey }.map(\.0))
    }

    /// Loads the limits of `bots` (every Bot when `nil`) whose numbers are over five minutes old.
    /// A Bot the gateway had no numbers for is asked once more shortly after: Hermes fetches them
    /// in the background the first time it's asked.
    public func refresh(_ bots: [Contact]? = nil) async {
        let profiles = (bots ?? agents()).map(Self.profile(of:))
        let due = profiles.filter { profile in
            !loading.contains(profile) && loadedAt[profile].map { now().timeIntervalSince($0) >= 5 * 60 } ?? true
        }
        let firstTime = due.filter { loadedAt[$0] == nil }
        await load(due)
        let empty = firstTime.filter { plans[$0]?.provider.limits.isEmpty ?? true }
        guard !empty.isEmpty else { return }
        try? await Task.sleep(for: retryAfter)
        await load(empty)
    }

    private func load(_ profiles: [String]) async {
        guard !profiles.isEmpty else { return }
        loading.formUnion(profiles)
        defer { loading.subtract(profiles) }
        let loads = profiles.map { profile in (profile, Task { try await fetch(profile) }) }
        for (profile, load) in loads {
            // A Bot that doesn't answer keeps what it had; one with no provider has nothing to show.
            guard let plan = try? await load.value else { continue }
            plans[profile] = plan
            loadedAt[profile] = now()
        }
    }

    /// Signing out or switching gateway forgets every number.
    func clear() {
        plans = [:]
        loadedAt = [:]
    }

    private static func profile(of contact: Contact) -> String { contact.details?.profile ?? contact.id }
}
