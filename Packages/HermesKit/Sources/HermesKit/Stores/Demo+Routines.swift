#if DEBUG
    import Foundation

    /// A past run in the demo, with what was said in it.
    struct DemoRun {
        let run: RoutineRun
        let messages: [HistoryMessage]
    }

    /// Routines kept in memory, for the demo and previews. Nothing leaves the device: Run Now waits
    /// a moment and adds a made-up run.
    @MainActor
    final class DemoRoutines: RoutineBackend {
        private var routines: [Routine]
        private var runsByRoutine: [String: [DemoRun]]
        private let runTime: Duration
        private var nextID = 1
        /// What New Routine offers, and the skills the agent has for them.
        var templates = DemoTemplate.all
        private let installedSkills: [Skill]

        /// `runTime`: how long Run Now takes.
        init(
            _ routines: [Routine], runs: [String: [DemoRun]], runTime: Duration = .seconds(4), skills: [Skill] = []
        ) {
            self.routines = routines
            self.runsByRoutine = runs
            self.runTime = runTime
            self.installedSkills = skills
        }

        func list() async throws -> [Routine] { routines }

        func setOn(_ on: Bool, id: String) async throws -> Routine? {
            try change(id) { routine in
                routine.copy(isOn: on, nextRun: on ? .now.addingTimeInterval(3600) : nil)
            }
        }

        func create(_ body: JSONValue) async throws -> Routine? {
            let schedule = body["schedule"]?.stringValue ?? ""
            try Self.check(schedule)
            let prompt = body["prompt"]?.stringValue ?? ""
            defer { nextID += 1 }
            let routine = Routine(
                id: "demo-\(nextID)", name: body["name"]?.stringValue?.nonBlank ?? String(prompt.prefix(50)),
                schedule: schedule, isOn: true, nextRun: .now.addingTimeInterval(3600), prompt: prompt,
                deliver: body["deliver"]?.stringValue ?? "local")
            routines.append(routine)
            return routine
        }

        func update(id: String, _ updates: JSONValue) async throws -> Routine? {
            if let schedule = updates["schedule"]?.stringValue { try Self.check(schedule) }
            return try change(id) { routine in
                Routine(
                    id: routine.id, name: updates["name"]?.stringValue ?? routine.name,
                    schedule: updates["schedule"]?.stringValue ?? routine.schedule, isOn: routine.isOn,
                    isFinished: routine.isFinished, nextRun: routine.nextRun, lastRun: routine.lastRun,
                    lastRunFailed: routine.lastRunFailed, prompt: updates["prompt"]?.stringValue ?? routine.prompt,
                    deliver: updates["deliver"]?.stringValue ?? routine.deliver,
                    scheduleText: updates["schedule"]?.stringValue ?? routine.scheduleText,
                    lastError: routine.lastError, worksWithoutPrompt: routine.worksWithoutPrompt)
            }
        }

        func delete(id: String) async throws {
            guard routines.contains(where: { $0.id == id }) else { throw Self.notFound }
            routines.removeAll { $0.id == id }
            runsByRoutine[id] = nil
        }

        func trigger(id: String) async throws -> Routine? {
            guard let routine = routines.first(where: { $0.id == id }) else { throw Self.notFound }
            let started = Date.now
            try await Task.sleep(for: runTime)
            let reply = "Ran “\(routine.name)” just now. Everything looks as it should, and nothing needs you."
            let run = DemoRun(
                run: RoutineRun(
                    id: "demo-run-\(UUID().uuidString)", started: started, status: .finished, preview: reply),
                messages: [
                    HistoryMessage(role: "user", text: routine.prompt.nonBlank ?? routine.name),
                    HistoryMessage(role: "assistant", text: reply),
                ])
            runsByRoutine[id, default: []].insert(run, at: 0)
            return try change(id) { $0.copy(isOn: true, nextRun: $0.nextRun, lastRun: started, lastRunFailed: false) }
        }

        func runs(id: String) async throws -> [RoutineRun] { (runsByRoutine[id] ?? []).map(\.run) }

        func messages(runID: String) async throws -> [HistoryMessage] {
            runsByRoutine.values.joined().first { $0.run.id == runID }?.messages ?? []
        }

        func templates() async throws -> [RoutineTemplate] { templates.map(\.template) }

        func create(template key: String, values: [String: String]) async throws -> JSONValue {
            guard let demo = templates.first(where: { $0.template.key == key }) else {
                throw GatewayError.http(status: 404, message: "Unknown blueprint: \(key)")
            }
            let template = demo.template
            // What Hermes's fill_blueprint refuses, in its words.
            for field in template.fields {
                let value = values[field.name] ?? field.defaultValue
                if value.isEmpty, !field.isOptional {
                    throw GatewayError.http(
                        status: 422, message: "missing required value: \(field.name) (\(field.label))")
                }
            }
            var filled = template.defaults
            filled.merge(values) { _, new in new }
            guard let schedule = template.schedule(filled), let prompt = RoutineTemplate.fill(demo.prompt, with: filled)
            else { throw GatewayError.http(status: 422, message: "a time is required") }
            defer { nextID += 1 }
            let deliver = filled["deliver"] ?? "origin"
            routines.append(
                Routine(
                    id: "demo-\(nextID)", name: template.title, schedule: schedule, isOn: true,
                    nextRun: .now.addingTimeInterval(3600), prompt: prompt, deliver: deliver,
                    worksWithoutPrompt: !demo.skills.isEmpty))
            return [
                "id": .string("demo-\(nextID)"), "name": .string(template.title), "prompt": .string(prompt),
                "schedule": ["kind": "cron", "expr": .string(schedule), "display": .string(schedule)],
                "schedule_display": .string(schedule), "enabled": true, "state": "scheduled",
                "next_run_at": .string(Date.now.addingTimeInterval(3600).formatted(.iso8601)),
                "deliver": .string(deliver), "skills": .array(demo.skills.map(JSONValue.string)),
            ]
        }

        func skills() async throws -> [Skill] { installedSkills }

        private func change(_ id: String, _ transform: (Routine) -> Routine) throws -> Routine {
            guard let index = routines.firstIndex(where: { $0.id == id }) else { throw Self.notFound }
            routines[index] = transform(routines[index])
            return routines[index]
        }

        private static let notFound = GatewayError.http(status: 404, message: "Job not found")

        /// Roughly what the gateway accepts, so the demo can show its message for the rest.
        private static func check(_ schedule: String) throws {
            let text = schedule.trimmingCharacters(in: .whitespaces).lowercased()
            let accepted =
                text.hasPrefix("every ") || text.hasPrefix("in ") || text.hasPrefix("weekdays")
                || text.split(separator: " ").count == 5 || text.wholeMatch(of: /\d+[mhd]/) != nil
                || text.wholeMatch(of: /\d{4}-\d{2}-\d{2}.*/) != nil
            guard !accepted else { return }
            throw GatewayError.http(
                status: 400,
                message: """
                    Invalid schedule '\(schedule)'. Use:
                      - Interval: '30m', 'every 30m', 'every 2h' (recurring)
                      - One-shot delay: 'in 30m', 'in 2h' (fires once)
                      - Weekly/daily: 'every monday 9am', 'weekdays at 9am' (recurring)
                      - Cron: '0 9 * * *' (cron expression)
                      - Timestamp: '2026-02-03T14:00:00' (one-shot at time)
                    """)
        }
    }

    extension DemoRoutines {
        /// The routines each demo agent has: Ops and Atlas have some, with past runs.
        static func list(for agent: String, now: Date, skills: [Skill] = []) -> RoutineList {
            let hours = { (count: Double) in now.addingTimeInterval(count * 3600) }
            switch agent {
            case "ops":
                let routines = [
                    Routine(
                        id: "health", name: "Morning health check", schedule: "0 8 * * *", isOn: true,
                        nextRun: hours(9), lastRun: hours(-15),
                        prompt: "Check CPU, memory and disk on all three servers. Tell me only what needs attention.",
                        deliver: "bot-chat:ops"),
                    Routine(
                        id: "backups", name: "Verify last night's backups", schedule: "0 6 * * *", isOn: true,
                        nextRun: hours(7), lastRun: hours(-17), lastRunFailed: true,
                        prompt: "Restore last night's database backup to the scratch server and check it opens.",
                        deliver: "local",
                        lastError: "The scratch server didn't answer on port 5432 within 60 seconds."),
                    Routine(
                        id: "costs", name: "Weekly cost report", schedule: "0 9 * * 1", isOn: true,
                        nextRun: hours(3 * 24),
                        prompt: "Compare this week's cloud costs with last week's and list anything that grew.",
                        deliver: "telegram:-100123456"),
                    Routine(
                        id: "certs", name: "Renew staging certificates", schedule: "0 3 1 * *", isOn: false,
                        prompt: "Renew the staging TLS certificates and restart the proxy.", deliver: "local"),
                ]
                let health = [
                    run(
                        "health-2", hours(-15), "Check CPU, memory and disk on all three servers.",
                        "All three servers are healthy.\n\n- **web-1**: CPU 12%, disk 41%\n- **web-2**: CPU 9%, disk 38%\n- **db-1**: CPU 22%, disk 67%\n\nNothing needs you today."
                    ),
                    run(
                        "health-1", hours(-39), "Check CPU, memory and disk on all three servers.",
                        "**db-1** is at 81% disk. The oldest WAL archives can go; say the word and I'll clear them."
                    ),
                ]
                let backups = [
                    DemoRun(
                        run: RoutineRun(
                            id: "backups-2", started: hours(-17), status: .failed,
                            preview: "The scratch server didn't answer on port 5432 within 60 seconds."),
                        messages: [
                            HistoryMessage(
                                role: "user", text: "Restore last night's database backup to the scratch server."),
                            HistoryMessage(
                                role: "assistant",
                                text:
                                    "I couldn't finish: the scratch server didn't answer on port 5432 within 60 seconds."
                            ),
                        ]),
                    run(
                        "backups-1", hours(-41), "Restore last night's database backup to the scratch server.",
                        "Restored 2.3 GB in 4 minutes. All 48 tables open and the row counts match production."),
                ]
                return RoutineList.sample(
                    routines, profile: "ops", runs: ["health": health, "backups": backups], skills: skills)
            case "atlas":
                let routines = [
                    Routine(
                        id: "pricing", name: "Competitor pricing watch", schedule: "0 9 * * 1-5", isOn: true,
                        nextRun: hours(14), lastRun: hours(-10),
                        prompt: "Check the three competitors' pricing pages and tell me what changed since yesterday.",
                        deliver: "bot-chat:atlas"),
                    Routine(
                        id: "papers", name: "New papers on vector search", schedule: "every 1440m", isOn: true,
                        nextRun: hours(20), lastRun: hours(-4),
                        prompt: "Find new papers on vector search from the last day and summarise the useful ones.",
                        deliver: "local"),
                    Routine(
                        id: "reading", name: "Export reading list", schedule: "0 18 * * 5", isOn: true,
                        nextRun: hours(4 * 24), lastRun: hours(-3 * 24), deliver: "local", worksWithoutPrompt: true),
                ]
                let pricing = [
                    run(
                        "pricing-1", hours(-10), "Check the three competitors' pricing pages.",
                        "Nobody changed their pricing since yesterday. Turbopuffer still has the lowest price at our size."
                    )
                ]
                let papers = [
                    run(
                        "papers-1", hours(-4), "Find new papers on vector search from the last day.",
                        "Two worth reading:\n\n1. **Faster HNSW rebuilds**: cuts index rebuild time by half.\n2. **Filtered search without a second index**: fits how we filter by team."
                    )
                ]
                let reading = [
                    DemoRun(
                        run: RoutineRun(
                            id: "cron_output:reading:2026-10-30_18-00-00", started: hours(-3 * 24), status: .finished,
                            preview: "Exported 14 saved articles to reading-list.md (3 new this week).",
                            isScriptOnly: true),
                        messages: [])
                ]
                return RoutineList.sample(
                    routines, profile: "atlas", runs: ["pricing": pricing, "papers": papers, "reading": reading],
                    skills: skills)
            default:
                return RoutineList.sample([], profile: agent, skills: skills)
            }
        }

        private static func run(_ id: String, _ started: Date, _ prompt: String, _ reply: String) -> DemoRun {
            DemoRun(
                run: RoutineRun(id: id, started: started, status: .finished, preview: reply),
                messages: [HistoryMessage(role: "user", text: prompt), HistoryMessage(role: "assistant", text: reply)])
        }
    }

    extension Routine {
        fileprivate func copy(isOn: Bool, nextRun: Date?, lastRun: Date? = nil, lastRunFailed: Bool? = nil)
            -> Routine
        {
            Routine(
                id: id, name: name, schedule: schedule, isOn: isOn, isFinished: isFinished, nextRun: nextRun,
                lastRun: lastRun ?? self.lastRun, lastRunFailed: lastRunFailed ?? self.lastRunFailed, prompt: prompt,
                deliver: deliver, scheduleText: scheduleText, lastError: lastRunFailed == false ? nil : lastError,
                worksWithoutPrompt: worksWithoutPrompt)
        }
    }
#endif
