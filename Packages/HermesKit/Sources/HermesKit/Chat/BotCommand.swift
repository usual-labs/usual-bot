import Foundation

/// The commands an agent ran with Hermes's `terminal` tool, for the terminal drawer's list.
public enum BotCommand {
    public static let toolName = "terminal"
    /// What a command printed, kept from its end: a long build log is mostly noise, and the
    /// offline cache keeps every step.
    static let outputLimit = 8_000

    /// The output as kept: the last `outputLimit` characters, starting at a line.
    static func kept(_ output: String) -> String {
        guard output.count > outputLimit else { return output }
        let tail = output.suffix(outputLimit)
        guard let newline = tail.firstIndex(of: "\n") else { return String(tail) }
        return String(tail[tail.index(after: newline)...])
    }
}

extension ToolStep {
    /// Reads a `terminal` call's command from its `args`, and its output and exit code from its
    /// `result` (`{"output", "exit_code", "error"}`).
    mutating func readCommand(args: JSONValue?, result: JSONValue? = nil) {
        guard name == BotCommand.toolName else { return }
        if let text = args?["command"]?.stringValue?.nonBlank { command = text }
        guard let result else { return }
        let printed = result["output"]?.stringValue ?? result.stringValue
        let error = result["error"]?.stringValue?.nonBlank
        let text = [printed?.nonBlank, error].compactMap { $0 }.joined(separator: "\n")
        if !text.isEmpty { output = BotCommand.kept(text) }
        exitCode = result["exit_code"]?.intValue
    }

    /// What ran: the full command when the gateway sent it, else its preview.
    public var commandLine: String { command ?? context }
}

extension ThreadState {
    /// Every `terminal` call in the chat as loaded, oldest first, with when it was shown.
    public var commands: [(step: ToolStep, date: Date?)] {
        items.flatMap { item -> [(step: ToolStep, date: Date?)] in
            guard case .activity(let steps) = item.content else { return [] }
            return steps.filter { $0.name == BotCommand.toolName }.map { ($0, item.date) }
        }
    }

    /// The running turn is running a command right now.
    public var isRunningCommand: Bool {
        guard isRunning, case .activity(let steps) = items.last?.content else { return false }
        return steps.contains { $0.state == .running && $0.name == BotCommand.toolName }
    }
}
