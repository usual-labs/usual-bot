import Foundation
import Testing

@testable import HermesKit

/// Hermes's notices for a background process and for helpers, in the shapes
/// `tools/process_registry_notifications.py` writes them, after `GatewayTurn` takes off the brackets
/// and the first line of a helper batch.
struct ResultReportTests {
    @Test func aProcessReportSaysHowItEndedWhatRanAndWhatItPrinted() throws {
        let report = try #require(
            ProcessReport.parse(
                """
                Background process proc_9 exited (exit code 1).
                Command: for f in *.log; do
                  grep -c ERROR "$f"
                done
                Output:
                app.log: 3
                worker.log: 0
                """))
        #expect(report.exitCode == 1)
        #expect(report.outcome == .failed)
        #expect(report.command == "for f in *.log; do\n  grep -c ERROR \"$f\"\ndone")
        #expect(report.output == "app.log: 3\nworker.log: 0")
    }

    @Test func aProcessThatFinishedOrWasStopped() throws {
        let finished = try #require(
            ProcessReport.parse(
                "Background process proc_1 completed normally (exit code 0).\nCommand: ./verify.sh\nOutput:\nok"))
        #expect(finished.outcome == .finished)
        let stopped = try #require(
            ProcessReport.parse(
                """
                Background process proc_2 terminated by Hermes (exit code -15, SIGTERM).
                Started by subagent sa-1 (delegate_task).
                Command: sleep 600
                Output:
                """))
        #expect(stopped.outcome == .stopped)
        #expect(stopped.command == "sleep 600")
        #expect(stopped.output.isEmpty)
    }

    @Test func aWatchMatchKeepsWhatMatched() throws {
        let report = try #require(
            ProcessReport.parse(
                """
                Background process proc_3 matched watch pattern "ERROR".
                Command: tail -f app.log
                Matched output:
                ERROR disk full
                """))
        #expect(report.outcome == .matched)
        #expect(report.exitCode == nil)
        #expect(report.output == "ERROR disk full")
    }

    @Test func somethingElseIsNotAProcessReport() {
        #expect(ProcessReport.parse("Cronjob finished.") == nil)
        #expect(ProcessReport.parse("Background process proc_1 completed normally (exit code 0).") == nil)
    }

    @Test func aHelperBatchSplitsIntoItsTasks() throws {
        let report = try #require(
            HelperReport.parse(
                """
                A background fan-out unit you dispatched earlier — 2 subagent(s) — has finished; its consolidated \
                results are below.

                Dispatched: 2026-11-17 12:41:36 (3m34s ago)
                Role: leaf   Model: claude-opus-5-5   Total duration: 215.3s

                --- ✓ TASK 1/2: Read the launch notes and list open questions  (status=completed, api_calls=16, \
                167.53s) ---
                I found **3 open questions**.
                - Pricing
                - Dates

                --- ✗ TASK 2/2: Check the staging deploy  (status=failed, 12.0s) ---
                (no summary — status=failed: provider error)
                """))
        #expect(report.seconds == 215.3)
        #expect(report.model == "claude-opus-5-5")
        #expect(
            report.tasks == [
                HelperReport.Task(
                    goal: "Read the launch notes and list open questions", succeeded: true, calls: 16,
                    seconds: 167.53, text: "I found **3 open questions**.\n- Pricing\n- Dates"),
                HelperReport.Task(
                    goal: "Check the staging deploy", succeeded: false, calls: nil, seconds: 12,
                    text: "(no summary — status=failed: provider error)"),
            ])
    }

    @Test func oneHelperIsOneTask() throws {
        let report = try #require(
            HelperReport.parse(
                """
                A background subagent you dispatched earlier has finished.

                Dispatched: 2026-11-17 12:41:36 (2m ago)
                Original goal: Summarise the support inbox
                Role: leaf
                Status: completed   API calls: 4   Duration: 61.2s
                --- RESULT ---
                Five tickets, none urgent.
                """))
        #expect(
            report.tasks == [
                HelperReport.Task(
                    goal: "Summarise the support inbox", succeeded: true, calls: 4, seconds: 61.2,
                    text: "Five tickets, none urgent.")
            ])
        #expect(report.seconds == 61.2)
    }

    /// What the chat holds after `GatewayTurn`, which is what the line parses.
    @Test func noticesParseAfterTheChatReadsThem() throws {
        let process = GatewayTurn.content(
            text: "[IMPORTANT: Background process proc_1 exited (exit code 2).\nCommand: make\nOutput:\nerror]",
            kind: "process_complete", title: "Background Process Finished: make")
        guard case .result(_, let processDetail) = process else { throw ReportError.notAResult }
        #expect(ProcessReport.parse(processDetail)?.exitCode == 2)

        let helpers = GatewayTurn.content(
            text: """
                [ASYNC DELEGATION BATCH COMPLETE — d1]
                A background fan-out unit you dispatched earlier — 1 subagent(s) — has finished.

                Role: leaf   Total duration: 3.0s

                --- ✓ TASK 1/1: Count the tickets  (status=completed, api_calls=1, 3.0s) ---
                Twelve.
                """,
            kind: "async_delegation_complete", title: nil)
        guard case .result(_, let helperDetail) = helpers else { throw ReportError.notAResult }
        #expect(HelperReport.parse(helperDetail)?.tasks.map(\.goal) == ["Count the tickets"])
    }

    private enum ReportError: Error { case notAResult }

    @Test func aReportWithNoTasksIsNotAHelperReport() {
        #expect(HelperReport.parse("A background subagent you dispatched earlier has finished.") == nil)
    }
}
