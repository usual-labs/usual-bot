import Foundation

extension ChatThread {
    /// How often a background task that may have finished out of sight is looked up.
    static let backgroundCheckInterval: Duration = .seconds(20)

    /// After the chat attaches again: replays what a short drop missed (the gateway keeps a live
    /// session's last 512 events), else tells side questions their answer is gone (Hermes doesn't
    /// keep them), then looks up background tasks still waiting in their stored sessions until
    /// they're answered (their answer may have gone to a session that's gone).
    func recoverMissed(rejoined: Bool) {
        recovery?.cancel()
        recovery = Task { [weak self] in
            guard let self else { return }
            if !(rejoined ? await replay() : false) { loseUnansweredWork() }
            await checkBackgroundTasks()
        }
    }

    /// Side answers and background results sent while this device was away. `false` when the
    /// gateway couldn't replay (restarted, or too much happened since).
    private func replay() async -> Bool {
        guard let sessionID, let channel = channel(),
            let result = try? await channel.call(
                "session.events.since", params: ["session_id": .string(sessionID), "last_seen": .number(Double(lastSeq))])
        else { return false }
        guard result["truncated"]?.boolValue != true, result["epoch"]?.stringValue == replayEpoch,
            case .array(let frames) = result["events"]
        else { return false }
        for frame in frames {
            guard let type = frame["type"]?.stringValue, type == "btw.complete" || type == "background.complete"
            else { continue }
            apply(
                GatewayEvent(
                    type: type, sessionID: sessionID, seq: frame["seq"]?.intValue, payload: frame["payload"] ?? [:]))
        }
        return true
    }

    /// Answers that can't arrive any more: they were meant for a session that's gone.
    private func loseUnansweredWork() {
        for index in sideQuestions.indices where sideQuestions[index].answer == .waiting {
            sideQuestions[index].answer = .failed(
                String(localized: "The answer was lost while Usual Bot was offline. Ask again."))
        }
        // A task the gateway never confirmed may not have started at all.
        for task in backgroundTasks where task.id.hasPrefix("local-") {
            state.addNotice(
                String(localized: "Usual Bot went offline as “\(task.task)” was starting; if no answer comes, start it again."))
        }
        backgroundTasks.removeAll { $0.id.hasPrefix("local-") }
    }

    /// Looks up each waiting background task's stored session until it has an answer.
    private func checkBackgroundTasks() async {
        while !Task.isCancelled, isAttached, let storedAnswer {
            let waiting = backgroundTasks.filter { !$0.id.hasPrefix("local-") }
            guard !waiting.isEmpty else { return }
            for task in waiting {
                if let answer = await storedAnswer(task.id) {
                    receiveBackgroundResult(["task_id": .string(task.id), "text": .string(answer)])
                }
            }
            try? await Task.sleep(for: Self.backgroundCheckInterval)
        }
    }
}
