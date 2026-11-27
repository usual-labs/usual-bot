import Foundation
import Observation

/// Which Bots have a routine running, so the sidebar shows them working. A run lives in its own
/// session, which no chat attaches to, so its events reach no one: this reads `live_execution`
/// from every profile's jobs (`/api/cron/jobs?profile=all`), which Hermes fills while a run holds
/// its claim. `cron.changed` only follows the gateway's launch profile, so the list is also read
/// with the roster: every minute, and more often while something runs, to see it end.
@MainActor
@Observable
public final class RunningRoutines {
    /// Profiles with a run in progress.
    public private(set) var profiles: Set<String> = []

    static let idleInterval: Duration = .seconds(60)
    static let busyInterval: Duration = .seconds(15)

    @ObservationIgnored private let fetch: @MainActor () async throws -> JSONValue
    @ObservationIgnored private var lastRead: ContinuousClock.Instant?
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(fetch: @escaping @MainActor () async throws -> JSONValue) {
        self.fetch = fetch
    }

    convenience init(auth: @escaping @MainActor () -> AuthSession?) {
        self.init {
            guard let auth = auth() else { throw GatewayError.disconnected }
            return try await auth.json(JSONValue.self, path: "/api/cron/jobs?profile=all")
        }
    }

    /// Reads the jobs when the last read is old enough; called with each roster read.
    func readIfDue(now: ContinuousClock.Instant = .now) {
        let interval = profiles.isEmpty ? Self.idleInterval : Self.busyInterval
        if let lastRead, now - lastRead < interval { return }
        read()
    }

    /// Reads the jobs now, unless a read is already under way.
    func read() {
        guard reading == nil else { return }
        lastRead = .now
        let generation = generation
        reading = Task { [weak self] in
            let jobs = try? await self?.fetch()
            guard let self, self.generation == generation else { return }
            self.reading = nil
            // A failed read keeps what was known; the next one corrects it.
            if let jobs { self.adopt(jobs) }
        }
    }

    func adopt(_ jobs: JSONValue) {
        guard case .array(let rows) = jobs else { return }
        let running = Set(
            rows.filter { if case .object = $0["live_execution"] { true } else { false } }
                .compactMap { $0["profile"]?.stringValue })
        if running != profiles { profiles = running }
    }

    /// Forgets everything: signed out, or switched to another gateway.
    func clear() {
        generation += 1
        reading?.cancel()
        reading = nil
        lastRead = nil
        profiles = []
    }

    #if DEBUG
        /// The demo: these profiles show a routine running.
        func showDemo(_ running: Set<String>) { profiles = running }
    #endif
}
