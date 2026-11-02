import Foundation
import Observation

/// Token use across the gateway's Bots for Settings › Usage: one `GET /api/analytics/usage` per
/// Bot's profile, since Hermes keeps usage in each profile's own store. A room member's turns are
/// stored in that member's profile, so they count toward the Bot that wrote them.
@MainActor
@Observable
public final class UsageOverview {
    /// The periods the official app offers.
    public enum Period: Int, CaseIterable, Identifiable, Sendable {
        case week = 7
        case month = 30
        case quarter = 90
        public var id: Int { rawValue }
    }

    public enum Phase: Equatable, Sendable {
        case loading
        case ready
        /// The gateway's Hermes predates the usage route.
        case unsupported
        case failed(String)
    }

    public struct BotUsage: Identifiable, Equatable, Sendable {
        public let contact: Contact
        public let report: UsageReport
        public var id: Contact.ID { contact.id }
    }

    private struct Snapshot {
        var phase: Phase = .loading
        var bots: [BotUsage] = []
        var problems: [String] = []
        var loadedAt: Date?
    }

    public var period: Period = .week
    private var snapshots: [Period: Snapshot] = [:]
    /// Periods being loaded; switching period mid-load starts the other one too.
    private var refreshing: Set<Period> = []

    @ObservationIgnored private let agents: @MainActor () -> [Contact]
    @ObservationIgnored private let fetch: @MainActor (_ profile: String, _ days: Int) async throws -> UsageReport
    @ObservationIgnored private let now: @MainActor () -> Date

    init(
        agents: @escaping @MainActor () -> [Contact],
        now: @escaping @MainActor () -> Date = { .now },
        fetch: @escaping @MainActor (_ profile: String, _ days: Int) async throws -> UsageReport
    ) {
        self.agents = agents
        self.now = now
        self.fetch = fetch
    }

    convenience init(auth: @escaping @MainActor () -> AuthSession?, agents: @escaping @MainActor () -> [Contact]) {
        self.init(agents: agents) { profile, days in
            guard let auth = auth() else { throw GatewayError.disconnected }
            let escaped = profile.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? profile
            // Hermes reads every session in the period, which takes a while on a big store.
            let json = try await auth.json(
                JSONValue.self, path: "/api/analytics/usage?days=\(days)&profile=\(escaped)", timeout: 60)
            return try UsageReport(json: json)
        }
    }

    public var phase: Phase { snapshots[period]?.phase ?? .loading }
    /// Bots that used anything, most first.
    public var bots: [BotUsage] { snapshots[period]?.bots ?? [] }
    /// Bots whose usage didn't load, or a refresh that failed over older numbers.
    public var problems: [String] { snapshots[period]?.problems ?? [] }
    public var loadedAt: Date? { snapshots[period]?.loadedAt }
    /// Every Bot's usage added up.
    public var combined: UsageReport { .combined(bots.map(\.report)) }
    public var today: Date { now() }
    public var isRefreshing: Bool { refreshing.contains(period) }

    /// Loads the period on screen for every Bot at once. Keeps the numbers already shown if the
    /// whole refresh fails.
    public func refresh() async {
        let period = self.period
        guard !refreshing.contains(period) else { return }
        refreshing.insert(period)
        defer { refreshing.remove(period) }
        let loads = agents().map { contact in
            (contact, Task { try await fetch(contact.details?.profile ?? contact.id, period.rawValue) })
        }
        var loaded: [BotUsage] = []
        var failures: [(Contact, any Error)] = []
        for (contact, load) in loads {
            do {
                loaded.append(BotUsage(contact: contact, report: try await load.value))
            } catch {
                failures.append((contact, error))
            }
        }
        var snapshot = snapshots[period] ?? Snapshot()
        if !loads.isEmpty, loaded.isEmpty, let (_, error) = failures.first {
            if snapshot.phase == .ready {
                snapshot.problems = [String(localized: "Couldn't refresh: \(AppModel.describe(error))")]
            } else if failures.allSatisfy({ Self.isMissingRoute($0.1) }) {
                snapshot.phase = .unsupported
            } else {
                snapshot.phase = .failed(AppModel.describe(error))
            }
        } else {
            snapshot.phase = .ready
            snapshot.bots = loaded.filter { !$0.report.isEmpty }
                .sorted { ($0.report.totalTokens, $1.contact.name) > ($1.report.totalTokens, $0.contact.name) }
            snapshot.problems = failures.map { contact, error in
                String(localized: "Couldn't load \(contact.name)'s usage: \(AppModel.describe(error))")
            }
            snapshot.loadedAt = now()
        }
        snapshots[period] = snapshot
    }

    /// Signing out forgets every number.
    func clear() {
        snapshots = [:]
        period = .week
    }

    /// A 404 for the route itself, as an older Hermes answers. An unknown profile is also a 404,
    /// but it says so.
    static func isMissingRoute(_ error: any Error) -> Bool {
        guard case .http(let status, let message) = error as? GatewayError else { return false }
        if status == 405 { return true }
        guard status == 404 else { return false }
        guard let message else { return true }
        return message == "Not Found" || message.hasPrefix("No such API endpoint")
    }
}
