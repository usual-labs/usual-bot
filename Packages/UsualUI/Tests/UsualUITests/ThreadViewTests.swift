import Foundation
import Testing

@testable import HermesKit
@testable import UsualUI

struct MarkdownBlockTests {
    private func kinds(_ markdown: String) -> [String] {
        MarkdownBlock.parse(markdown).map { block in
            switch block {
            case .paragraph(let text): return "p:" + String(text.characters)
            case .heading(let level, let text): return "h\(level):" + String(text.characters)
            case .listItem(let marker, let depth, let text): return "li\(depth)\(marker)" + String(text.characters)
            case .quote(let text): return "q:" + String(text.characters)
            case .code(let language, let code): return "code(\(language ?? "-")):" + code
            case .rule: return "hr"
            case .media(let path, let voice): return (voice ? "voice:" : "media:") + path
            case .image(let url, let alt): return "img(\(alt)):" + url.absoluteString
            case .table(let table): return "table:" + table.lines.joined(separator: " / ")
            }
        }
    }

    @Test func mediaLinesBecomeFilesBetweenTheText() {
        let reply = """
            Here's the chart.
            MEDIA:/home/h/.hermes/profiles/ops/cache/cpu.png
              MEDIA:`/home/h/reports/Q3 summary.pdf`
            Anything else?
            """
        #expect(
            kinds(reply) == [
                "p:Here's the chart.", "media:/home/h/.hermes/profiles/ops/cache/cpu.png",
                "media:/home/h/reports/Q3 summary.pdf", "p:Anything else?",
            ])
    }

    @Test func voiceMarkersHideAndMakeTheAudioVoice() {
        let reply = """
            Here you go.
            [[audio_as_voice]]
            MEDIA:/home/h/.hermes/cache/audio/tts_20261102_071502_118204.ogg
            """
        #expect(kinds(reply) == ["p:Here you go.", "voice:/home/h/.hermes/cache/audio/tts_20261102_071502_118204.ogg"])
        #expect(kinds("[[as_document]]\nMEDIA:/tmp/a.mp3") == ["media:/tmp/a.mp3"])
        #expect(kinds("```\n[[audio_as_voice]]\n```") == ["code(-):[[audio_as_voice]]"])
    }

    @Test func plainImagePathsShowAsImages() {
        let reply = """
            Cartoon version saved to:

            /home/armin/.hermes/cache/generated/images/openai_gpt-image_20261024_002430.png
            """
        #expect(
            kinds(reply) == [
                "p:Cartoon version saved to:",
                "media:/home/armin/.hermes/cache/generated/images/openai_gpt-image_20261024_002430.png",
            ])
        #expect(
            kinds("Saved it as `/tmp/out/chart.PNG`, and the notes in /tmp/out/notes.md.") == [
                "p:Saved it as /tmp/out/chart.PNG, and the notes in /tmp/out/notes.md.", "media:/tmp/out/chart.PNG",
            ])
        #expect(
            kinds("See https://example.com/a/b.png and ~/x.png") == ["p:See https://example.com/a/b.png and ~/x.png"])
    }

    @Test func mediaInsideCodeStaysCode() {
        let reply = """
            ```
            MEDIA:/tmp/example.png
            ```
            """
        #expect(kinds(reply) == ["code(-):MEDIA:/tmp/example.png"])
    }

    @Test func markdownImagesComeOutOfTheirParagraph() {
        #expect(
            kinds("Generated: ![a red fox](https://fal.media/files/fox.png) done") == [
                "p:Generated:  done", "img(a red fox):https://fal.media/files/fox.png",
            ])
        #expect(kinds("![](/home/h/.hermes/images/cat.png)") == ["media:/home/h/.hermes/images/cat.png"])
    }

    @Test func splitsCommonBlocks() {
        let markdown = """
            ## Release

            Done. **All** tests pass.

            - bumped version
            - added changelog
              1. nested step

            > note

            ```swift
            let x = 1
            ```

            ---
            """
        #expect(
            kinds(markdown) == [
                "h2:Release", "p:Done. All tests pass.", "li0•bumped version", "li0•added changelog",
                "li11.nested step", "q:note", "code(swift):let x = 1", "hr",
            ])
    }

    @Test func tablesKeepTheirColumns() throws {
        let markdown = """
            Disk use:

            | Path | Size | Note |
            | --- | ---: | :---: |
            | `/var/lib/docker` | 38 GB | |
            | /home | 2 GB | **old** |

            Done.
            """
        #expect(
            kinds(markdown) == [
                "p:Disk use:", "table:Path  ·  Size  ·  Note / /var/lib/docker  ·  38 GB  ·   / /home  ·  2 GB  ·  old",
                "p:Done.",
            ])
        guard case .table(let table) = MarkdownBlock.parse(markdown)[1] else { throw TableMissing() }
        #expect(table.alignments == [.leading, .trailing, .center])
        #expect(table.rows.count == 2)
    }

    @Test func twoTablesInARowStayApart() {
        let markdown = """
            | A |
            | - |
            | 1 |

            | B |
            | - |
            | 2 |
            """
        #expect(kinds(markdown) == ["table:A / 1", "table:B / 2"])
    }

    private struct TableMissing: Error {}

    @Test func wideColumnsGiveWayFirst() {
        // Room for all: every column keeps its width.
        #expect(TableLayout.fitted(ideal: [100, 200], minimum: [90, 90], into: 400) == [100, 200])
        // Short of room: the narrow column keeps its width, the wide ones share the rest.
        #expect(TableLayout.fitted(ideal: [60, 280, 280], minimum: [60, 90, 90], into: 360) == [60, 150, 150])
        // Never below the narrowest, even if the table is then too wide and has to scroll.
        #expect(TableLayout.fitted(ideal: [280, 280], minimum: [90, 90], into: 120) == [90, 90])
    }

    @Test func plainTextIsOneParagraph() {
        #expect(kinds("Just text") == ["p:Just text"])
    }

    // Agents write a line per item and expect it to show that way, as the gateway's other
    // platforms do; CommonMark would run the lines together into one.
    @Test func singleLineBreaksStay() {
        let reply = "Mercury: The smallest planet.\nVenus: The hottest planet.\nEarth: Home."
        #expect(kinds(reply) == ["p:Mercury: The smallest planet.\nVenus: The hottest planet.\nEarth: Home."])
        #expect(kinds("One.\nTwo.\n\nThree.") == ["p:One.\nTwo.", "p:Three."])
        #expect(kinds("> quoted\n> twice") == ["q:quoted\ntwice"])
    }

    @Test func lineBreaksLeaveListsHeadingsAndTablesAlone() {
        #expect(kinds("- one\n- two\n  still two\n1. first") == ["li0•one", "li0•two\nstill two", "li01.first"])
        #expect(kinds("# Title\nText\nMore") == ["h1:Title", "p:Text\nMore"])
        #expect(kinds("Setext\n---\nAfter") == ["h2:Setext", "p:After"])
        #expect(kinds("| A |\n| - |\n| 1 |\n| 2 |") == ["table:A / 1 / 2"])
        #expect(kinds("Use `a`\nthen `b`") == ["p:Use a\nthen b"])
    }

    @Test func lineBreaksLeaveCodeAlone() {
        #expect(kinds("Run:\n```sh\nmake\nmake test\n```\nDone.") == ["p:Run:", "code(sh):make\nmake test", "p:Done."])
        #expect(kinds("Run:\n\n    make\n    make test") == ["p:Run:", "code(-):make\nmake test"])
        #expect(kinds("> ```\n> a\n> b\n> ```") == ["code(-):a\nb"])
        // A reply still being written may not have closed its fence yet.
        #expect(kinds("```\na\nb") == ["code(-):a\nb"])
    }

    @Test func lineBreaksIgnoreTrailingSpaceAndCarriageReturns() {
        #expect(kinds("a \nb   \nc\t\nd") == ["p:a\nb\nc\nd"])
        #expect(kinds("a\\\nb") == ["p:a\nb"])
        #expect(kinds("a\r\nb\r\n\r\nc\rd") == ["p:a\nb", "p:c\nd"])
        #expect(kinds("```\r\nx\r\ny\r\n```") == ["code(-):x\ny"])
        #expect(kinds("End.  \n\nNext.  ") == ["p:End.", "p:Next."])
    }
}

struct ActivitySummaryTests {
    private func step(_ name: String, _ state: ToolStep.State = .done, duration: TimeInterval? = nil) -> ToolStep {
        ToolStep(id: UUID().uuidString, name: name, context: "", duration: duration, state: state)
    }

    @Test func describesWhatTheAgentDid() {
        let steps = [
            step("read_file", duration: 2), step("read_file"), step("patch"), step("terminal", duration: 46.4),
            step("terminal"),
        ]
        #expect(
            ActivitySummary.line(for: steps, agent: "Hermes")
                == "Hermes read 2 files, edited 1 file and ran 2 commands · 48s")
    }

    @Test func singleKindsAndOthers() {
        #expect(ActivitySummary.line(for: [step("web_search")], agent: "Scout") == "Scout browsed the web")
        #expect(ActivitySummary.line(for: [step("memory"), step("todo_list")], agent: "Ops") == "Ops used 2 tools")
        #expect(
            ActivitySummary.line(for: [step("terminal"), step("memory")], agent: "Ops")
                == "Ops ran 1 command and used 1 other tool")
    }

    @Test func showsProgressAndFailures() {
        #expect(ActivitySummary.current(in: [step("read_file"), step("terminal", .running)]) == "Running a command")
        #expect(ActivitySummary.current(in: [step("todo_list", .running)]) == "Using todo list")
        #expect(ActivitySummary.current(in: [step("terminal")]) == nil)
        #expect(
            ActivitySummary.line(for: [step("terminal", .failed, duration: 75)], agent: "Hermes")
                == "Hermes ran 1 command · 1m 15s · 1 failed")
    }
}

struct RoutineStatusTests {
    private let now = Date(timeIntervalSince1970: 1_792_735_200)  // 2026-10-23 06:00 UTC

    @Test func describesScheduleAndState() {
        let next = Routine(
            id: "1", name: "Brief", schedule: "weekdays at 8am", isOn: true, nextRun: now.addingTimeInterval(86_400))
        #expect(RoutineStatus.status(for: next, now: now).hasPrefix("next "))
        #expect(RoutineSchedule.plainWords(next.schedule) == "Weekdays at 8am")
        let paused = Routine(id: "2", name: "Recap", schedule: "every friday", isOn: false)
        #expect(RoutineStatus.status(for: paused, now: now) == "Paused")
        let done = Routine(id: "3", name: "Once", schedule: "", isOn: true, isFinished: true)
        #expect(RoutineStatus.status(for: done, now: now) == "Finished")
        let failed = Routine(id: "4", name: "Check", schedule: "hourly", isOn: true, lastRunFailed: true)
        #expect(RoutineStatus.status(for: failed, now: now) == "Last run failed")
        let explained = Routine(
            id: "5", name: "Check", schedule: "hourly", isOn: true, lastRunFailed: true, lastError: "Provider timed out"
        )
        #expect(RoutineStatus.status(for: explained, now: now) == "Last run failed: Provider timed out")
        // The detail shows the failure on its own line, so its status leaves it out.
        #expect(RoutineStatus.status(for: explained, failure: false, now: now) == "")
    }
}

struct WorkingRowTests {
    @Test func aReplyWrittenOutOfSightSaysSo() {
        var state = ThreadState()
        state.sendLocally("Hi")
        #expect(WorkingRow.text(for: state) == "Thinking…")
        state.apply(GatewayEvent(type: "message.delta", sessionID: "s1", seq: nil, payload: ["text": "Hel"]))
        #expect(WorkingRow.text(for: state) == "Writing…")
    }
}
