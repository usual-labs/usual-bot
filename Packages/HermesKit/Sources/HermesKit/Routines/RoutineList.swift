import Foundation
import Observation

/// One agent's routines, loaded from the gateway's cron routes and changed there.
@MainActor
@Observable
public final class RoutineList {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// How the last Run Now went, shown on that routine until the next one.
    public struct RunOutcome: Equatable, Sendable {
        public let succeeded: Bool
        public let message: String
    }

    /// The Hermes profile the routines belong to.
    public let profile: String
    public private(set) var routines: [Routine] = []
    public private(set) var phase: Phase = .loading
    /// The last switch that didn't go through, shown under the list.
    public private(set) var problem: String?
    /// Routines Run Now is waiting on. The gateway answers only when the run ends.
    public private(set) var running: Set<Routine.ID> = []
    public private(set) var outcomes: [Routine.ID: RunOutcome] = [:]
    /// The fill-in templates New Routine offers, once loaded.
    public private(set) var templates: [RoutineTemplate] = []
    public private(set) var templatePhase: TemplatePhase = .loading

    /// Whether New Routine can offer templates yet.
    public enum TemplatePhase: Equatable, Sendable {
        case loading
        case ready
        /// None to offer: an older gateway, or it couldn't be reached. New Routine is a blank form.
        case unavailable
    }

    private let backend: any RoutineBackend
    private var refreshing = false
    private var loadingTemplates = false
    /// The gateway answered about templates, even with none: no need to ask again.
    private var templatesSettled = false

    init(profile: String, auth: @escaping @MainActor () -> AuthSession?) {
        self.profile = profile
        self.backend = GatewayRoutines(profile: profile, auth: auth)
    }

    init(profile: String, backend: any RoutineBackend) {
        self.profile = profile
        self.backend = backend
    }

    /// Reloads the list. Keeps showing the old one if the reload fails.
    public func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let loaded = try await backend.list()
            // Reloaded as the tab opens and every 30 seconds: an unchanged list mustn't redraw.
            if loaded != routines { routines = loaded }
            if phase != .ready { phase = .ready }
        } catch GatewayError.disconnected {
            // Not signed in yet: nothing to say until there's a gateway to ask.
        } catch {
            if phase != .ready { phase = .failed(AppModel.describe(error)) }
        }
    }

    /// Pauses or resumes a routine. The switch moves at once and moves back if the gateway refuses.
    public func setOn(_ on: Bool, for routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        problem = nil
        routines[index] = routine.with(isOn: on)
        Task {
            do {
                if let updated = try await backend.setOn(on, id: routine.id) { replace(updated) }
            } catch {
                if let current = routines.firstIndex(where: { $0.id == routine.id }) { routines[current] = routine }
                problem =
                    on
                    ? String(localized: "Couldn't turn on “\(routine.name)”: \(Self.describe(error))")
                    : String(localized: "Couldn't pause “\(routine.name)”: \(Self.describe(error))")
            }
        }
    }

    /// Creates a routine. Throws with the gateway's reason, such as a schedule it can't read.
    @discardableResult
    public func create(_ draft: RoutineDraft) async throws -> Routine? {
        let created = try await backend.create(draft.createBody(profile: profile))
        if let created { routines.append(created) }
        await refresh()
        return created.flatMap { new in routines.first { $0.id == new.id } } ?? created
    }

    /// Loads the templates once. A gateway without them settles on none; one that can't be reached
    /// is asked again on the next call.
    public func loadTemplates() async {
        guard !loadingTemplates, !templatesSettled else { return }
        loadingTemplates = true
        defer { loadingTemplates = false }
        do {
            templates = try await backend.templates()
            templatePhase = templates.isEmpty ? .unavailable : .ready
            templatesSettled = true
        } catch {
            templatePhase = .unavailable
        }
    }

    /// Creates a routine from `template`: Hermes fills in its prompt and schedule from `values` and
    /// adds the skills it uses. Says which of those skills the agent can't load, so the form can
    /// tell the user now rather than leave the first run without them.
    public func create(
        from template: RoutineTemplate, values: [String: String], delivery: RoutineDelivery
    ) async throws -> TemplateRoutine {
        let job = try await backend.create(
            template: template.key, values: template.filled(values, delivery: delivery, profile: profile))
        guard let created = Routine(job: job) else { throw GatewayError.invalidResponse }
        routines.append(created)
        var missing: [TemplateRoutine.MissingSkill] = []
        // Against no skills, every skill it uses is missing: ask for the agent's only if it uses any.
        if !TemplateRoutine.missing(in: job, installed: []).isEmpty, let installed = try? await backend.skills() {
            missing = TemplateRoutine.missing(in: job, installed: installed)
        }
        await refresh()
        return TemplateRoutine(routine: routines.first { $0.id == created.id } ?? created, missingSkills: missing)
    }

    /// Saves what changed in `draft`. Nothing changed sends nothing.
    @discardableResult
    public func save(_ draft: RoutineDraft, to routine: Routine) async throws -> Routine {
        let updates = draft.updates(from: routine, profile: profile)
        guard updates != [:] else { return routine }
        let updated = try await backend.update(id: routine.id, updates)
        if let updated { replace(updated) }
        return updated ?? routine
    }

    public func delete(_ routine: Routine) async throws {
        try await backend.delete(id: routine.id)
        routines.removeAll { $0.id == routine.id }
        outcomes[routine.id] = nil
    }

    /// Runs a routine now, in the background: `running` holds it until the gateway answers, which
    /// can take minutes, and `outcomes` then says how it went.
    public func runNow(_ routine: Routine) {
        guard !running.contains(routine.id) else { return }
        running.insert(routine.id)
        outcomes[routine.id] = nil
        Task {
            defer { running.remove(routine.id) }
            do {
                let after = try await backend.trigger(id: routine.id)
                if let after { replace(after) }
                outcomes[routine.id] = Self.outcome(of: after ?? routine)
                await refresh()
            } catch GatewayError.http(status: 409, _) {
                outcomes[routine.id] = RunOutcome(
                    succeeded: false, message: String(localized: "It's already running. Check Past Runs soon."))
            } catch GatewayError.timedOut, GatewayError.unreachable, GatewayError.cancelled {
                outcomes[routine.id] = RunOutcome(
                    succeeded: false,
                    message: String(
                        localized: "Lost touch with the gateway while it ran. It may still be going: check Past Runs."
                    ))
            } catch {
                outcomes[routine.id] = RunOutcome(
                    succeeded: false, message: String(localized: "Couldn't run it: \(Self.describe(error))"))
            }
        }
    }

    /// The routine's latest runs, newest first.
    public func runs(of routine: Routine) async throws -> [RoutineRun] {
        try await backend.runs(id: routine.id)
    }

    /// What an agent run said, as a chat shows it. Script-only runs have only their preview.
    public func transcript(of run: RoutineRun) async throws -> [TranscriptItem] {
        ThreadState(history: try await backend.messages(runID: run.id), running: false).items
    }

    /// An error in words for the routine screens: the gateway's own reason when it gives one, such
    /// as how to write a schedule, without the status code.
    public static func describe(_ error: any Error) -> String {
        if case .http(let status, let message?) = error as? GatewayError, (400..<500).contains(status) {
            return message
        }
        return AppModel.describe(error)
    }

    private static func outcome(of routine: Routine) -> RunOutcome {
        if routine.lastRunFailed {
            let reason = routine.lastError.map { String(localized: "It failed: \($0)") }
            return RunOutcome(succeeded: false, message: reason ?? String(localized: "It failed."))
        }
        return RunOutcome(succeeded: true, message: String(localized: "Finished. The result is in Past Runs."))
    }

    private func replace(_ routine: Routine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) { routines[index] = routine }
    }

    #if DEBUG
        /// Tests and previews: a list already showing `routines`.
        static func sample(
            _ routines: [Routine], profile: String = "sample", runs: [String: [DemoRun]] = [:],
            runTime: Duration = .seconds(4), skills: [Skill] = []
        ) -> RoutineList {
            let list = RoutineList(
                profile: profile, backend: DemoRoutines(routines, runs: runs, runTime: runTime, skills: skills))
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
            lastRun: lastRun, lastRunFailed: lastRunFailed, prompt: prompt, deliver: deliver,
            scheduleText: scheduleText, lastError: lastError, worksWithoutPrompt: worksWithoutPrompt)
    }
}

extension CharacterSet {
    /// RFC 3986 unreserved characters: letters, digits and `-._~`.
    static let urlUnreservedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}
