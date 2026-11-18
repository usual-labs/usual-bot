import HermesKit
import SwiftUI

/// Work Hermes finished on its own, as one line with the report a click away. Nobody wrote it, so
/// it isn't a bubble and has no message actions. A background process and helpers get their own
/// line, read from Hermes's notice; anything else, or a notice that isn't in the shape expected,
/// shows its text as it came.
struct ResultLine: View {
    let title: String
    let detail: String

    var body: some View {
        if let process = ProcessReport.parse(detail) {
            ProcessResultLine(report: process)
        } else if let helpers = HelperReport.parse(detail) {
            HelperResultLine(report: helpers)
        } else {
            FoldedRow(symbol: "terminal", opens: !detail.isEmpty) {
                Text(title).lineLimit(1)
            } rows: {
                // Routine output and other Bots' messages are written words, not terminal text.
                ReportPeek(text: detail, style: .markdown)
            }
        }
    }
}

/// How a background command ended and what it was, with the command and its output behind it.
/// Hermes's own title is the whole command, which for a shell loop filled the line with code.
private struct ProcessResultLine: View {
    let report: ProcessReport

    var body: some View {
        FoldedRow(symbol: symbol, tint: report.outcome == .failed ? Theme.danger : Theme.secondaryInk) {
            Text(title).lineLimit(1)
        } rows: {
            Caption(text: String(localized: "Command"))
            ReportPeek(text: report.command, style: .code)
            if report.output.isEmpty {
                Caption(text: String(localized: "No output"))
            } else {
                Caption(text: report.outcome == .matched ? String(localized: "Matched") : String(localized: "Output"))
                ReportPeek(text: report.output, style: .code)
            }
        }
    }

    private var title: String {
        let command = report.command.split(separator: "\n").first.map(String.init) ?? ""
        return [outcome, command].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var outcome: String {
        switch report.outcome {
        case .finished: String(localized: "Background command finished")
        case .failed:
            report.exitCode.map { String(localized: "Background command failed with exit code \($0)") }
                ?? String(localized: "Background command failed")
        case .stopped: String(localized: "Background command stopped")
        case .matched: String(localized: "Background command printed what it watches for")
        case .running: String(localized: "Background command still running")
        }
    }

    private var symbol: String {
        switch report.outcome {
        case .finished: "checkmark.circle"
        case .failed: "xmark.circle"
        case .stopped: "stop.circle"
        case .matched: "eye"
        case .running: "terminal"
        }
    }
}

/// What helpers sent back: how many and how long on the line, then each helper's goal and its
/// report in Markdown. Hermes's notice put all of it, and its instructions to the model, in one
/// monospaced wall.
private struct HelperResultLine: View {
    let report: HelperReport

    private var failed: Int { report.tasks.filter { !$0.succeeded }.count }

    var body: some View {
        FoldedRow(
            symbol: failed > 0 ? "xmark.circle" : "arrow.triangle.branch",
            tint: failed > 0 ? Theme.danger : Theme.secondaryInk
        ) {
            Text(title).lineLimit(1)
        } rows: {
            if let task = report.tasks.first, report.tasks.count == 1 {
                if !task.goal.isEmpty { Caption(text: task.goal) }
                ReportPeek(text: task.text, style: .markdown)
            } else {
                ForEach(Array(report.tasks.enumerated()), id: \.offset) { _, task in
                    HelperTaskRow(task: task)
                }
            }
        }
    }

    private var title: String {
        let count = report.tasks.count
        var pieces = [
            count == 1
                ? (failed > 0 ? String(localized: "A helper failed") : String(localized: "A helper finished"))
                : String(localized: "\(count) helpers finished")
        ]
        if count > 1, failed > 0 { pieces.append(String(localized: "\(failed) failed")) }
        if let seconds = report.seconds, seconds >= 1 { pieces.append(ActivitySummary.duration(seconds)) }
        return pieces.joined(separator: " · ")
    }
}

private struct HelperTaskRow: View {
    let task: HelperReport.Task

    var body: some View {
        FoldedRow(
            symbol: task.succeeded ? "checkmark.circle" : "xmark.circle",
            tint: task.succeeded ? Theme.secondaryInk : Theme.danger
        ) {
            HStack(spacing: 8) {
                Text(task.goal.isEmpty ? String(localized: "Helper") : task.goal)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .layoutPriority(-1)
                if let detail {
                    Text(detail).lineLimit(1)
                }
            }
            .scaledFont(size: 12.5)
        } rows: {
            ReportPeek(text: task.text, style: .markdown)
        }
        .accessibilityHint(task.succeeded ? Text("Finished") : Text("Failed"))
    }

    private var detail: String? {
        let calls = task.calls.map { $0 == 1 ? String(localized: "1 call") : String(localized: "\($0) calls") }
        let time = task.seconds.flatMap { $0 >= 1 ? ActivitySummary.duration($0) : nil }
        let pieces = [calls, time].compactMap(\.self)
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }
}

struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(size: 12, weight: .medium)
            .foregroundStyle(Theme.secondaryInk)
            .lineLimit(2)
            .padding(.leading, 4)
    }
}

/// A report's first lines, fading out, with Show All under them. A long report used to scroll in a
/// box of its own inside the scrolling chat, which a trackpad or a thumb scrolled by mistake.
struct ReportPeek: View {
    enum Style { case code, markdown }

    let text: String
    let style: Style
    @State private var showsAll = false

    nonisolated static let peekLines = 8
    /// Helpers write paragraphs on one line each, so lines alone don't keep the peek short.
    nonisolated static let peekCharacters = 700

    var body: some View {
        let lines = Self.lineCount(text)
        let peek = Self.peek(text)
        let folds = peek != text
        let faded = folds && !showsAll
        VStack(alignment: .leading, spacing: 6) {
            content(faded ? peek : text, faded: faded)
            if folds {
                Button(showsAll ? String(localized: "Show Less") : String(localized: "Show All \(lines) Lines")) {
                    withAnimation(.smooth(duration: 0.2)) { showsAll.toggle() }
                }
                .buttonStyle(.clickable)
                .scaledFont(size: 12.5, weight: .medium)
                .foregroundStyle(Theme.secondaryInk)
                .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder private func content(_ shown: String, faded: Bool) -> some View {
        switch style {
        case .code:
            Text(shown)
                .scaledFont(size: 12.5, design: .monospaced)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fadesOut(faded)
                .padding(12)
                .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 12))
        case .markdown:
            MarkdownView(shown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fadesOut(faded)
                .padding(.leading, 4)
        }
    }

    /// The start of `text` the peek shows, or `text` itself when it's short enough to show whole.
    /// Cut at a line, or at a word when the first line alone runs long.
    nonisolated static func peek(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > peekLines + 2 || text.count > peekCharacters + 200 else { return text }
        var kept: [Substring] = []
        var characters = 0
        for line in lines.prefix(peekLines) {
            if !kept.isEmpty, characters + line.count > peekCharacters { break }
            kept.append(line)
            characters += line.count + 1
        }
        var peek = kept.joined(separator: "\n")
        if peek.count > peekCharacters {
            let cut = peek.prefix(peekCharacters)
            peek = String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]) + "…"
        }
        return peek
    }

    nonisolated static func lineCount(_ text: String) -> Int {
        text.reduce(into: 1) { count, character in if character.isNewline { count += 1 } }
    }
}

private extension View {
    /// The bottom of a peek fading into what follows, so it reads as cut short.
    @ViewBuilder func fadesOut(_ fades: Bool) -> some View {
        if fades {
            mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom)
            }
        } else {
            self
        }
    }
}
