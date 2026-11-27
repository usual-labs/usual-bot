import Foundation

/// Background processes the agent started from this chat (a terminal command run in the
/// background, such as one watching a pull request) keep it working after its reply ends. Hermes
/// lists a live session's own with `process.list`; nothing announces one starting or ending, so the
/// list is read when the chat attaches and after each reply, and again while any still run.
extension ChatThread {
    static let processCheckInterval: Duration = .seconds(20)

    func checkProcesses() {
        processCheck?.cancel()
        guard let sessionID, let channel = channel() else { return }
        processCheck = Task { [weak self] in
            // A gateway without the call refuses it; nothing then counts as running.
            guard let result = try? await channel.call("process.list", params: ["session_id": .string(sessionID)])
            else { return }
            guard let self, !Task.isCancelled, self.sessionID == sessionID else { return }
            self.adoptProcesses(result["processes"])
            guard !self.runningProcesses.isEmpty else { return }
            try? await Task.sleep(for: Self.processCheckInterval)
            guard !Task.isCancelled else { return }
            self.checkProcesses()
        }
    }

    func adoptProcesses(_ processes: JSONValue?) {
        guard case .array(let rows) = processes else { return runningProcesses = [] }
        let running = rows.filter { $0["status"]?.stringValue == "running" }.compactMap {
            $0["session_id"]?.stringValue
        }
        if running != runningProcesses { runningProcesses = running }
    }
}
