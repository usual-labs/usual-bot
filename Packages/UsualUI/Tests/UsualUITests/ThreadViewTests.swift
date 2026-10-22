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
            }
        }
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

    @Test func tableRowsBecomeLines() {
        let markdown = """
            | Path | Size |
            | --- | --- |
            | /var/lib/docker | 38 GB |
            """
        #expect(kinds(markdown) == ["p:Path  ·  Size", "p:/var/lib/docker  ·  38 GB"])
    }

    @Test func plainTextIsOneParagraph() {
        #expect(kinds("Just text") == ["p:Just text"])
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
        #expect(ActivitySummary.line(for: [step("terminal", .running)], agent: "Hermes") == "Hermes is working…")
        #expect(
            ActivitySummary.line(for: [step("terminal", .failed, duration: 75)], agent: "Hermes")
                == "Hermes ran 1 command · 1m 15s · 1 failed")
    }
}
