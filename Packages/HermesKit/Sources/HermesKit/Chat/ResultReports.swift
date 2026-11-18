import Foundation

/// A background process's notice, read from the text Hermes gives the model
/// (`format_process_notification` in `tools/process_registry_notifications.py`). `nil` when the text
/// isn't in that shape, and the chat shows it as it came.
public struct ProcessReport: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case finished, failed, stopped, matched, running
    }

    public let outcome: Outcome
    public let exitCode: Int?
    public let command: String
    public let output: String

    private static let outputLabels: Set<String> = ["Output:", "Matched output:", "Output since last heartbeat:"]

    /// `text`: the notice without its `[IMPORTANT: …]` brackets, its first line saying how it ended.
    public static func parse(_ text: String) -> ProcessReport? {
        let lines = text.components(separatedBy: "\n")
        guard let head = lines.first, head.hasPrefix("Background process "),
            let commandLine = lines.firstIndex(where: { $0.hasPrefix("Command: ") }),
            let outputLine = lines[commandLine...].firstIndex(where: { outputLabels.contains($0) })
        else { return nil }
        let command =
            ([String(lines[commandLine].dropFirst("Command: ".count))] + lines[(commandLine + 1)..<outputLine])
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let output = lines[(outputLine + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let exitCode = Pattern.first(#"\(exit code (-?\d+)"#, in: head).flatMap { Int($0) }
        let outcome: Outcome =
            if head.contains(" matched watch pattern") {
                .matched
            } else if head.contains(" heartbeat #") {
                .running
            } else if head.contains(" terminated by ") {
                .stopped
            } else if exitCode == 0 {
                .finished
            } else {
                .failed
            }
        return ProcessReport(outcome: outcome, exitCode: exitCode, command: command, output: output)
    }
}

/// What helpers sent back, read from Hermes's notice (`_format_batch_delegation` and
/// `_format_async_delegation`): one task for each helper, with its own report. `nil` when the text
/// isn't in that shape, and the chat shows it as it came.
public struct HelperReport: Equatable, Sendable {
    public struct Task: Equatable, Sendable {
        public let goal: String
        public let succeeded: Bool
        public let calls: Int?
        public let seconds: Double?
        /// The helper's own words, Markdown.
        public let text: String

        public init(goal: String, succeeded: Bool, calls: Int?, seconds: Double?, text: String) {
            self.goal = goal
            self.succeeded = succeeded
            self.calls = calls
            self.seconds = seconds
            self.text = text
        }
    }

    public let tasks: [Task]
    /// The whole batch, start to finish.
    public let seconds: Double?
    public let model: String?

    /// `text`: the notice without its first line, `[ASYNC DELEGATION … COMPLETE — <id>]`.
    public static func parse(_ text: String) -> HelperReport? {
        let model = Pattern.first(#"(?m)^Role: .*Model: (\S+)"#, in: text)
        if let batch = batch(text, model: model) { return batch }
        return single(text, model: model)
    }

    /// `--- ✓ TASK 1/4: <goal>  (status=completed, api_calls=16, 167.53s) ---`, then that task's report.
    private static let taskHeader = #"^--- (✓|✗|⚠) TASK \d+/\d+(?:: (.*?))?  \(status=([^,)]+)(.*)\) ---$"#

    private static func batch(_ text: String, model: String?) -> HelperReport? {
        var tasks: [Task] = []
        var current: (goal: String, succeeded: Bool, calls: Int?, seconds: Double?)?
        var body: [String] = []
        func finish() {
            guard let task = current else { return }
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            tasks.append(
                Task(goal: task.goal, succeeded: task.succeeded, calls: task.calls, seconds: task.seconds, text: text))
        }
        for line in text.components(separatedBy: "\n") {
            if let header = Pattern.groups(taskHeader, in: line) {
                finish()
                let rest = header[3] ?? ""
                current = (
                    goal: header[1] ?? "", succeeded: header[0] == "✓",
                    calls: Pattern.first(#"api_calls=(\d+)"#, in: rest).flatMap { Int($0) },
                    seconds: Pattern.first(#", ([\d.]+)s"#, in: rest).flatMap { Double($0) }
                )
                body = []
            } else if current != nil {
                body.append(line)
            }
        }
        finish()
        guard !tasks.isEmpty else { return nil }
        let total = Pattern.first(#"Total duration: ([\d.]+)s"#, in: text).flatMap { Double($0) }
        return HelperReport(tasks: tasks, seconds: total, model: model)
    }

    private static func single(_ text: String, model: String?) -> HelperReport? {
        guard let result = text.range(of: "\n--- RESULT ---\n"),
            let status = Pattern.first(#"(?m)^Status: (\S+)"#, in: text)
        else { return nil }
        let head = String(text[..<result.lowerBound])
        let seconds = Pattern.first(#"(?m)^Status: .*Duration: ([\d.]+)s"#, in: head).flatMap { Double($0) }
        let task = Task(
            goal: Pattern.first(#"(?m)^Original goal: (.*)$"#, in: head) ?? "",
            succeeded: status == "completed",
            calls: Pattern.first(#"(?m)^Status: .*API calls: (\d+)"#, in: head).flatMap { Int($0) },
            seconds: seconds,
            text: text[result.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines))
        return HelperReport(tasks: [task], seconds: seconds, model: model)
    }
}

/// Regular expressions over Hermes's notices, which are machine-written but not structured.
private enum Pattern {
    /// The first capture group of the first match.
    static func first(_ pattern: String, in text: String) -> String? {
        groups(pattern, in: text)?.first ?? nil
    }

    /// Every capture group of the first match, `nil` for a group that didn't take part.
    static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
