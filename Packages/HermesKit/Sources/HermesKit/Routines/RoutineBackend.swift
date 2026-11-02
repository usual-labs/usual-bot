import Foundation

/// Where a `RoutineList` reads and changes routines: the gateway's cron routes, or the demo.
@MainActor
protocol RoutineBackend: AnyObject {
    func list() async throws -> [Routine]
    func setOn(_ on: Bool, id: String) async throws -> Routine?
    func create(_ body: JSONValue) async throws -> Routine?
    func update(id: String, _ updates: JSONValue) async throws -> Routine?
    func delete(id: String) async throws
    /// Runs the routine now and answers when the run ends.
    func trigger(id: String) async throws -> Routine?
    func runs(id: String) async throws -> [RoutineRun]
    func messages(runID: String) async throws -> [HistoryMessage]
    /// The fill-in templates New Routine offers. Empty on a gateway without them.
    func templates() async throws -> [RoutineTemplate]
    /// Has the gateway fill in template `key` with `values` and create the routine. Answers the job.
    func create(template key: String, values: [String: String]) async throws -> JSONValue
    /// The agent's skills, to tell which ones a new routine can't load.
    func skills() async throws -> [Skill]
}

/// The gateway's `/api/cron/jobs` routes for one profile.
@MainActor
final class GatewayRoutines: RoutineBackend {
    /// A run can take many minutes, and the trigger route answers only when it ends.
    static let triggerTimeout: TimeInterval = 30 * 60
    static let runLimit = 30

    private let profile: String
    private let auth: @MainActor () -> AuthSession?

    init(profile: String, auth: @escaping @MainActor () -> AuthSession?) {
        self.profile = profile
        self.auth = auth
    }

    func list() async throws -> [Routine] {
        guard case .array(let rows) = try await call("/api/cron/jobs") else { throw GatewayError.invalidResponse }
        return rows.compactMap(Routine.init(job:))
    }

    func setOn(_ on: Bool, id: String) async throws -> Routine? {
        Routine(job: try await call("/api/cron/jobs/\(Self.escape(id))/\(on ? "resume" : "pause")", method: "POST"))
    }

    func create(_ body: JSONValue) async throws -> Routine? {
        Routine(job: try await call("/api/cron/jobs", method: "POST", body: body))
    }

    func update(id: String, _ updates: JSONValue) async throws -> Routine? {
        Routine(job: try await call("/api/cron/jobs/\(Self.escape(id))", method: "PUT", body: ["updates": updates]))
    }

    func delete(id: String) async throws {
        _ = try await call("/api/cron/jobs/\(Self.escape(id))", method: "DELETE")
    }

    func trigger(id: String) async throws -> Routine? {
        Routine(
            job: try await call(
                "/api/cron/jobs/\(Self.escape(id))/trigger", method: "POST", timeout: Self.triggerTimeout))
    }

    func runs(id: String) async throws -> [RoutineRun] {
        let page = try await call("/api/cron/jobs/\(Self.escape(id))/runs", query: "&limit=\(Self.runLimit)")
        guard case .array(let rows) = page["runs"] else { throw GatewayError.invalidResponse }
        return rows.compactMap(RoutineRun.init(row:))
    }

    func messages(runID: String) async throws -> [HistoryMessage] {
        let page = try await call("/api/sessions/\(Self.escape(runID))/messages", query: "&inline_images=false")
        guard case .array(let rows) = page["messages"] else { throw GatewayError.invalidResponse }
        return rows.compactMap(HistoryMessage.init(storedRow:))
    }

    func templates() async throws -> [RoutineTemplate] {
        do {
            return try RoutineTemplate.catalog(try await call("/api/cron/blueprints"))
        } catch GatewayError.http(status: 404, _), GatewayError.http(status: 405, _) {
            return []  // Older than templates.
        }
    }

    func create(template key: String, values: [String: String]) async throws -> JSONValue {
        let body: JSONValue = ["blueprint": .string(key), "values": .object(values.mapValues(JSONValue.string))]
        return try await call("/api/cron/blueprints/instantiate", method: "POST", body: body)
    }

    func skills() async throws -> [Skill] {
        guard let auth = auth() else { throw GatewayError.disconnected }
        return try await auth.json([Skill].self, path: "/api/skills?profile=\(Self.escape(profile))")
    }

    private func call(
        _ route: String, query: String = "", method: String = "GET", body: JSONValue? = nil, timeout: TimeInterval = 30
    ) async throws -> JSONValue {
        guard let auth = auth() else { throw GatewayError.disconnected }
        return try await auth.json(
            JSONValue.self, path: "\(route)?profile=\(Self.escape(profile))\(query)", method: method, body: body,
            timeout: timeout)
    }

    static func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? component
    }
}
