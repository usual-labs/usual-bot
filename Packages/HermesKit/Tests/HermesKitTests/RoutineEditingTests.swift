import Foundation
import Testing

@testable import HermesKit

/// A job shaped like `cron/jobs.py`'s normalised record.
private func job(
    id: String = "a1b2c3d4e5f6", name: String = "Morning brief", deliver: JSONValue = "bot-chat:job-scout",
    lastStatus: String? = "ok", lastError: String? = nil
) -> JSONValue {
    [
        "id": .string(id), "name": .string(name), "prompt": "Summarise my inbox",
        "schedule": ["kind": "cron", "expr": "0 8 * * 1-5", "display": "0 8 * * 1-5"],
        "schedule_display": "0 8 * * 1-5", "enabled": true, "state": "scheduled",
        "next_run_at": "2026-10-24T08:00:00+02:00", "last_run_at": "2026-10-23T08:00:03+02:00",
        "last_status": lastStatus.map(JSONValue.string) ?? .null,
        "last_error": lastError.map(JSONValue.string) ?? .null, "deliver": deliver, "skills": [],
    ]
}

private func text(_ value: JSONValue) -> String {
    String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
}

private func body(_ request: URLRequest) -> JSONValue? {
    request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
}

struct RoutineFieldTests {
    @Test func readsWhatTheFormsNeed() throws {
        let routine = try #require(Routine(job: job()))
        #expect(routine.prompt == "Summarise my inbox")
        #expect(routine.deliver == "bot-chat:job-scout")
        #expect(routine.scheduleText == "0 8 * * 1-5")
        #expect(routine.lastError == nil)
        #expect(!routine.worksWithoutPrompt)

        let failed = try #require(Routine(job: job(lastStatus: "error", lastError: "Provider timed out")))
        #expect(failed.lastError == "Provider timed out")
        let listed = try #require(Routine(job: job(deliver: ["telegram", "local"])))
        #expect(listed.deliver == "telegram,local")
    }

    @Test func aResultThatWasntPostedIsKeptApartFromAFailedRun() throws {
        // Seen on a real gateway: the run worked, posting it into the Bot Chat didn't.
        var record = job()
        if case .object(var fields) = record {
            fields["last_delivery_error"] = "bot-chat delivery to profile 'job-scout' unverified: not_found"
            record = .object(fields)
        }
        let routine = try #require(Routine(job: record))
        #expect(!routine.lastRunFailed)
        #expect(routine.deliveryError == "bot-chat delivery to profile 'job-scout' unverified: not_found")
        #expect(try #require(Routine(job: job())).deliveryError == nil)
    }

    @Test func aOneOffIsEditedByItsTime() throws {
        let once: JSONValue = [
            "id": "x", "schedule": ["kind": "once", "run_at": "2026-11-03T09:00:00+01:00"],
            "schedule_display": "once at 2026-11-03 09:00",
        ]
        let routine = try #require(Routine(job: once))
        #expect(routine.schedule == "once at 2026-11-03 09:00")
        #expect(routine.scheduleText == "2026-11-03T09:00:00+01:00")
    }

    @Test func deliveryChoices() {
        #expect(RoutineDelivery(deliver: "bot-chat", profile: "scout") == .thisChat)
        #expect(RoutineDelivery(deliver: "bot-chat:Scout", profile: "scout") == .thisChat)
        #expect(RoutineDelivery(deliver: "local", profile: "scout") == .pastRunsOnly)
        #expect(RoutineDelivery(deliver: "bot-chat:other", profile: "scout") == .elsewhere("bot-chat:other"))
        #expect(RoutineDelivery.thisChat.value(profile: "scout") == "bot-chat:scout")
        #expect(RoutineDelivery.places("telegram:-1001,discord", profile: "scout") == "Telegram and Discord")
        #expect(RoutineDelivery.places("bot-chat:other", profile: "scout") == "other's chat")
    }

    @Test func aDraftSendsOnlyWhatChanged() throws {
        let routine = try #require(Routine(job: job(deliver: "telegram:-1001")))
        var draft = RoutineDraft(routine, profile: "job-scout")
        #expect(draft.delivery == .elsewhere("telegram:-1001"))
        #expect(draft.updates(from: routine, profile: "job-scout") == [:])

        draft.prompt = "Summarise my inbox and calendar"
        #expect(draft.updates(from: routine, profile: "job-scout") == ["prompt": "Summarise my inbox and calendar"])

        draft.delivery = .pastRunsOnly
        draft.schedule = " every 2h "
        draft.name = "  "
        #expect(
            draft.updates(from: routine, profile: "job-scout") == [
                "prompt": "Summarise my inbox and calendar", "schedule": "every 2h", "deliver": "local",
            ])
    }

    @Test func aNewRoutinePostsInThisChatByDefault() {
        let draft = RoutineDraft(prompt: " Check the build ", schedule: "0 9 * * *")
        #expect(draft.isComplete())
        #expect(!RoutineDraft(prompt: "Check", schedule: " ").isComplete())
        #expect(
            draft.createBody(profile: "scout") == [
                "name": "", "prompt": "Check the build", "schedule": "0 9 * * *", "deliver": "bot-chat:scout",
            ])
    }
}

struct RoutineScheduleTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    @Test func cronAndIntervalsInPlainWords() {
        // The time format puts a narrow no-break space before AM and PM.
        let words = { RoutineSchedule.plainWords($0, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ") }
        #expect(words("0 9 * * *") == "Every day at 9:00 AM")
        #expect(words("30 8 * * 1-5") == "Weekdays at 8:30 AM")
        #expect(words("0 9 * * 1") == "Every Monday at 9:00 AM")
        #expect(words("0 18 * * SUN") == "Every Sunday at 6:00 PM")
        #expect(words("0 3 1 * *") == "Monthly on the 1st at 3:00 AM")
        #expect(words("0 * * * *") == "Every hour")
        #expect(words("*/15 * * * *") == "Every 15 minutes")
        #expect(words("every 120m") == "Every 2 hours")
        #expect(words("every 1440m") == "Every day")
        #expect(words("every 45m") == "Every 45 minutes")
        #expect(words("every monday 9am") == "Every monday 9am")
        #expect(words("0 9 1-7 * 1") == "0 9 1-7 * 1")
    }

    @Test func presetsRoundTrip() {
        for preset in RoutineSchedule.Preset.allCases where preset != .custom {
            let choice = RoutineSchedule.Choice(preset: preset, hour: 7, minute: 45, weekday: 4)
            let expression = try! #require(choice.expression)
            let read = RoutineSchedule.Choice(expression)
            #expect(read.preset == preset)
            if preset.hasTime { #expect(read.hour == 7 && read.minute == 45) }
            if preset == .weekly { #expect(read.weekday == 4) }
        }
        #expect(RoutineSchedule.Choice("every monday 9am").preset == .custom)
        #expect(RoutineSchedule.Choice("0 9 * * 7").weekday == 0)
    }
}

@MainActor
struct RoutineChangeTests {
    private func list(_ http: ScriptedHTTP) -> RoutineList {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, provider: "basic", userID: "u"),
            store: MemoryTokenStore(), http: http)
        return RoutineList(profile: "job-scout", auth: { auth })
    }

    private let base = "http://100.101.102.103:9119/api/cron/jobs"

    @Test func createsARoutine() async throws {
        let http = ScriptedHTTP { request in
            request.httpMethod == "POST" ? (200, text(job(id: "new"))) : (200, text([job(id: "new")]))
        }
        let routines = list(http)
        let created = try await routines.create(RoutineDraft(prompt: "Summarise my inbox", schedule: "0 8 * * 1-5"))

        #expect(created?.id == "new")
        let post = http.requests[0]
        #expect(post.url?.absoluteString == "\(base)?profile=job-scout")
        #expect(body(post)?["deliver"] == "bot-chat:job-scout")
        #expect(routines.routines.map(\.id) == ["new"])
    }

    @Test func aRejectedScheduleSaysWhyInTheGatewaysWords() async {
        let routines = list(ScriptedHTTP { _ in (400, #"{"detail":"Invalid schedule 'sometime'. Use: …"}"#) })
        await #expect {
            try await routines.create(RoutineDraft(prompt: "Hi", schedule: "sometime"))
        } throws: { RoutineList.describe($0) == "Invalid schedule 'sometime'. Use: …" }
    }

    @Test func savingSendsOnlyTheChanges() async throws {
        let http = ScriptedHTTP { request in
            if request.httpMethod == "PUT" { return (200, text(job(name: "Inbox"))) }
            return (200, text([job()]))
        }
        let routines = list(http)
        await routines.refresh()
        let routine = routines.routines[0]

        try await routines.save(RoutineDraft(routine, profile: "job-scout"), to: routine)
        #expect(http.requests.count == 1)  // Nothing changed, nothing sent.

        var draft = RoutineDraft(routine, profile: "job-scout")
        draft.name = "Inbox"
        try await routines.save(draft, to: routine)
        let put = http.requests[1]
        #expect(put.url?.absoluteString == "\(base)/a1b2c3d4e5f6?profile=job-scout")
        #expect(body(put) == ["updates": ["name": "Inbox"]])
        #expect(routines.routines[0].name == "Inbox")
    }

    @Test func deletes() async throws {
        let http = ScriptedHTTP { request in
            request.httpMethod == "DELETE" ? (200, #"{"ok":true}"#) : (200, text([job()]))
        }
        let routines = list(http)
        await routines.refresh()
        try await routines.delete(routines.routines[0])
        #expect(http.requests[1].httpMethod == "DELETE")
        #expect(routines.routines.isEmpty)
    }

    @Test func runNowWaitsLongAndSaysHowItWent() async throws {
        let http = ScriptedHTTP { request in
            if request.url?.path.hasSuffix("/trigger") == true {
                return (200, text(job(lastStatus: "error", lastError: "Provider timed out")))
            }
            return (200, text([job()]))
        }
        let routines = list(http)
        await routines.refresh()
        routines.runNow(routines.routines[0])
        #expect(routines.running == ["a1b2c3d4e5f6"])

        try await waitUntilOnMain { routines.running.isEmpty }
        let trigger = try #require(http.requests.first { $0.url?.path.hasSuffix("/trigger") == true })
        #expect(trigger.httpMethod == "POST")
        #expect(trigger.timeoutInterval >= 30 * 60)
        #expect(routines.outcomes["a1b2c3d4e5f6"] == .init(succeeded: false, message: "It failed: Provider timed out"))
    }

    @Test func runNowWhileRunningSaysSo() async throws {
        let http = ScriptedHTTP { request in
            if request.url?.path.hasSuffix("/trigger") == true {
                return (409, #"{"detail":"Job is already running or was claimed by another scheduler"}"#)
            }
            return (200, text([job()]))
        }
        let routines = list(http)
        await routines.refresh()
        routines.runNow(routines.routines[0])
        try await waitUntilOnMain { routines.outcomes["a1b2c3d4e5f6"] != nil }
        #expect(routines.outcomes["a1b2c3d4e5f6"]?.message == "It's already running. Check Past Runs soon.")
    }

    @Test func aRunsPreviewIsntHermessCronInstructions() throws {
        // Seen on a real gateway: an agent run's preview is the first message Hermes sent it.
        let row: JSONValue = [
            "id": "cron_a1_20261102_233200", "source": "cron", "started_at": 1_792_735_203.0,
            "ended_at": 1_792_735_260.0, "end_reason": "cron_complete",
            "preview": "[IMPORTANT: You are running as a scheduled cron job. DELIVERY: your final response will be",
        ]
        #expect(try #require(RoutineRun(row: row)).preview == nil)
    }

    @Test func pastRunsAndWhatTheySaid() async throws {
        let runs: JSONValue = [
            "runs": [
                [
                    "id": "cron_a1b2c3d4e5f6_20261023_080003", "source": "cron", "started_at": 1_792_735_203.0,
                    "ended_at": 1_792_735_260.0, "end_reason": "cron_complete", "preview": "All clear",
                ],
                [
                    "id": "local-9", "source": "cron", "started_at": 1_792_800_000.0, "ended_at": .null,
                    "is_active": true,
                ],
                [
                    "id": "cron_output:a1b2c3d4e5f6:2026-10-22_08-00-00", "source": "cron_output",
                    "started_at": 1_792_648_800.0, "title": "FAILED · exit 1", "preview": "exit 1",
                ],
            ],
            "limit": 30,
        ]
        let messages: JSONValue = [
            "messages": [
                ["role": "user", "content": "Summarise my inbox", "timestamp": 1.0],
                ["role": "assistant", "content": "", "tool_calls": [["id": "t1"]]],
                ["role": "tool", "content": "{}", "tool_name": "search_mail", "tool_call_id": "t1"],
                ["role": "user", "content": "[System: retry]", "display_kind": "hidden"],
                ["role": "assistant", "content": "Two emails need you."],
            ]
        ]
        let http = ScriptedHTTP { request in
            if request.url?.path.hasSuffix("/runs") == true { return (200, text(runs)) }
            if request.url?.path.hasSuffix("/messages") == true { return (200, text(messages)) }
            return (200, text([job()]))
        }
        let routines = list(http)
        await routines.refresh()
        let found = try await routines.runs(of: routines.routines[0])

        #expect(found.map(\.status) == [.finished, .running, .failed])
        #expect(found[2].isScriptOnly && !found[0].isScriptOnly)
        #expect(found[0].started == Date(timeIntervalSince1970: 1_792_735_203))
        #expect(http.requests[1].url?.query == "profile=job-scout&limit=30")

        let items = try await routines.transcript(of: found[0]).map(\.content)
        #expect(
            http.requests[2].url?.absoluteString
                == "http://100.101.102.103:9119/api/sessions/cron_a1b2c3d4e5f6_20261023_080003/messages?profile=job-scout&inline_images=false"
        )
        #expect(items.count == 3)
        #expect(items.first == .user("Summarise my inbox"))
        #expect(items.last == .assistant("Two emails need you."))
    }

    @Test func theDemoRunsLocally() async throws {
        let routine = Routine(id: "r", name: "Check", schedule: "0 9 * * *", isOn: false, prompt: "Check")
        let routines = RoutineList.sample([routine], runTime: .zero)
        routines.runNow(routine)
        try await waitUntilOnMain { routines.outcomes["r"] != nil }
        #expect(routines.outcomes["r"]?.succeeded == true)
        #expect(routines.routines[0].isOn)  // Running a paused routine turns it on, as on a gateway.
        let runs = try await routines.runs(of: routine)
        #expect(runs.count == 1)
        #expect(try await routines.transcript(of: runs[0]).count == 2)

        await #expect {
            try await routines.create(RoutineDraft(prompt: "Hi", schedule: "sometime"))
        } throws: { RoutineList.describe($0).hasPrefix("Invalid schedule 'sometime'") }
    }
}
