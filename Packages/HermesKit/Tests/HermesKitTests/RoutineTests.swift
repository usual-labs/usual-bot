import Foundation
import Testing

@testable import HermesKit

/// A job shaped like `cron/jobs.py`'s normalised record.
private func job(
    id: String = "a1b2c3d4e5f6", name: String = "Morning brief", state: String = "scheduled", enabled: Bool = true,
    next: String? = "2026-10-24T08:00:00+02:00", lastStatus: String? = "ok"
) -> JSONValue {
    [
        "id": .string(id), "name": .string(name), "prompt": "Summarise my inbox",
        "schedule": ["kind": "cron", "expr": "0 8 * * 1-5", "display": "0 8 * * 1-5"],
        "schedule_display": "weekdays at 8am", "enabled": .bool(enabled), "state": .string(state),
        "next_run_at": next.map(JSONValue.string) ?? .null, "last_run_at": "2026-10-23T08:00:03.512345+02:00",
        "last_status": lastStatus.map(JSONValue.string) ?? .null, "deliver": "bot-chat",
    ]
}

private func text(_ value: JSONValue) -> String {
    String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
}

struct RoutineParsingTests {
    @Test func readsAJob() throws {
        let routine = try #require(Routine(job: job()))
        #expect(routine.name == "Morning brief")
        #expect(routine.schedule == "weekdays at 8am")
        #expect(routine.isOn)
        #expect(!routine.isFinished)
        #expect(routine.nextRun == Date(timeIntervalSince1970: 1_792_821_600))
        // Microseconds may or may not survive parsing; the second is what matters.
        #expect(abs((routine.lastRun?.timeIntervalSince1970 ?? 0) - 1_792_735_203) < 1)
        #expect(!routine.lastRunFailed)
    }

    @Test func pausedFinishedAndFailedJobs() throws {
        #expect(try #require(Routine(job: job(state: "paused", next: nil))).isOn == false)
        #expect(try #require(Routine(job: job(enabled: false))).isOn == false)
        #expect(try #require(Routine(job: job(state: "completed"))).isFinished)
        #expect(try #require(Routine(job: job(lastStatus: "error"))).lastRunFailed)
        #expect(Routine(job: ["name": "no id"]) == nil)
    }
}

@MainActor
struct RoutineListTests {
    private func list(_ http: ScriptedHTTP) -> RoutineList {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, provider: "basic", userID: "u"),
            store: MemoryTokenStore(), http: http)
        return RoutineList(profile: "job-scout", auth: { auth })
    }

    @Test func loadsTheProfilesJobs() async throws {
        let http = ScriptedHTTP { _ in (200, text([job(), job(id: "b", name: "Weekly recap", state: "paused")])) }
        let routines = list(http)
        await routines.refresh()

        #expect(routines.phase == .ready)
        #expect(routines.routines.map(\.name) == ["Morning brief", "Weekly recap"])
        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "http://100.101.102.103:9119/api/cron/jobs?profile=job-scout")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer a")
    }

    @Test func pausingCallsTheGatewayAndKeepsItsAnswer() async throws {
        let http = ScriptedHTTP { request in
            if request.httpMethod == "POST" { return (200, text(job(state: "paused", next: nil))) }
            return (200, text([job()]))
        }
        let routines = list(http)
        await routines.refresh()
        routines.setOn(false, for: routines.routines[0])
        #expect(routines.routines[0].isOn == false)  // Moves at once.

        try await waitUntilOnMain { http.requests.count == 2 }
        #expect(
            http.requests[1].url?.absoluteString
                == "http://100.101.102.103:9119/api/cron/jobs/a1b2c3d4e5f6/pause?profile=job-scout")
        #expect(http.requests[1].httpMethod == "POST")
        #expect(routines.problem == nil)
    }

    @Test func refusedSwitchMovesBackAndSaysWhy() async throws {
        let http = ScriptedHTTP { request in
            if request.httpMethod == "POST" { return (404, #"{"detail":"Job not found"}"#) }
            return (200, text([job(state: "paused", next: nil)]))
        }
        let routines = list(http)
        await routines.refresh()
        routines.setOn(true, for: routines.routines[0])
        #expect(routines.routines[0].isOn)

        try await waitUntilOnMain { routines.problem != nil }
        #expect(routines.routines[0].isOn == false)
        #expect(routines.problem?.contains("Job not found") == true)
    }

    @Test func failedFirstLoadShowsAnError() async {
        let routines = list(ScriptedHTTP { _ in (500, #"{"detail":"boom"}"#) })
        await routines.refresh()
        #expect(routines.phase == .failed("boom (HTTP 500)"))
    }
}
