import Foundation
import Observation

/// One agent's routines, loaded from the gateway's cron routes and switched on or off there.
@MainActor
@Observable
public final class RoutineList {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// The Hermes profile the routines belong to.
    public let profile: String
    public private(set) var routines: [Routine] = []
    public private(set) var phase: Phase = .loading
    /// The last switch that didn't go through, shown under the list.
    public private(set) var problem: String?

    private let auth: @MainActor () -> AuthSession?
    private var refreshing = false

    init(profile: String, auth: @escaping @MainActor () -> AuthSession?) {
        self.profile = profile
        self.auth = auth
    }

    /// Reloads the list. Keeps showing the old one if the reload fails.
    public func refresh() async {
        guard !refreshing, let auth = auth() else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let jobs = try await auth.json(JSONValue.self, path: path("/api/cron/jobs"))
            guard case .array(let rows) = jobs else { throw GatewayError.invalidResponse }
            routines = rows.compactMap(Routine.init(job:))
            phase = .ready
        } catch {
            if phase != .ready { phase = .failed(AppModel.describe(error)) }
        }
    }

    /// Pauses or resumes a routine. The switch moves at once and moves back if the gateway refuses.
    public func setOn(_ on: Bool, for routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }), let auth = auth() else { return }
        problem = nil
        routines[index] = routine.with(isOn: on)
        Task {
            do {
                let verb = on ? "resume" : "pause"
                let job = try await auth.json(
                    JSONValue.self, path: path("/api/cron/jobs/\(Self.escape(routine.id))/\(verb)"), method: "POST")
                if let updated = Routine(job: job), let current = routines.firstIndex(where: { $0.id == updated.id }) {
                    routines[current] = updated
                }
            } catch {
                if let current = routines.firstIndex(where: { $0.id == routine.id }) { routines[current] = routine }
                problem =
                    on
                    ? String(localized: "Couldn't turn on “\(routine.name)”: \(AppModel.describe(error))")
                    : String(localized: "Couldn't pause “\(routine.name)”: \(AppModel.describe(error))")
            }
        }
    }

    private func path(_ route: String) -> String {
        "\(route)?profile=\(Self.escape(profile))"
    }

    private static func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? component
    }

    #if DEBUG
        /// Tests and previews: a list already showing `routines`.
        static func sample(_ routines: [Routine]) -> RoutineList {
            let list = RoutineList(profile: "sample", auth: { nil })
            list.routines = routines
            list.phase = .ready
            return list
        }
    #endif
}

extension Routine {
    fileprivate func with(isOn: Bool) -> Routine {
        Routine(
            id: id, name: name, schedule: schedule, isOn: isOn, isFinished: isFinished, nextRun: isOn ? nextRun : nil,
            lastRun: lastRun, lastRunFailed: lastRunFailed)
    }
}

extension CharacterSet {
    /// RFC 3986 unreserved characters: letters, digits and `-._~`.
    static let urlUnreservedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}
