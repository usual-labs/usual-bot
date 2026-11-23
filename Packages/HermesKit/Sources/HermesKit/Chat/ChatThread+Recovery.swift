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
        // Only what's waiting now can be lost: the chat already takes new questions and tasks.
        let unanswered = Set(
            sideQuestions.filter { $0.answer == .waiting }.map(\.id) + backgroundTasks.map(\.id))
        recovery = Task { [weak self] in
            guard let self else { return }
            if !(rejoined ? await replay() : false) { loseUnansweredWork(unanswered) }
            await checkBackgroundTasks()
        }
    }

    /// Another device's message reaches this one only as a turn starting, without its words. The
    /// gateway's queue lists them as soon as the turn starts, but not its images: so the words show
    /// now, and the stored row replaces them once the turn ends (`finishTurnElsewhere`). A long
    /// reply would otherwise leave the chat without what it answers for minutes. Turns Hermes
    /// starts itself (routines, goals, other Bots' messages, under IDs `["producer",…]` and
    /// `bot:…`) and widget prompts (`widget-…`) wait for the stored row, which says what they were.
    func showTurnElsewhere(from info: JSONValue?) {
        guard let start = elsewhereTurnStart, elsewherePrompt == nil, case .array(let rows) = info?["pending"],
            let row = rows.first(where: { $0["status"] == "started" && $0["steering"]?.boolValue != true }),
            let id = row["input_id"]?.stringValue, !["[", "bot:", Self.widgetPrefix].contains(where: id.hasPrefix),
            !sentDirectly.contains(id), !queue.contains(where: { $0.id == id }),
            let text = row["text"]?.stringValue?.nonBlank, !state.hiddenPrompts.contains(text),
            let item = state.insertPrompt(HistoryMessage(role: "user", text: text), at: start)
        else { return }
        elsewherePrompt = (item, text)
    }

    /// Looks up another device's message once its turn is stored, as Hermes's own app does. Only
    /// it is put in: reloading would take you from what you're reading. A turn that failed or was
    /// stopped may not be stored, so its row is taken only if it's the message shown already.
    func finishTurnElsewhere(_ payload: JSONValue) {
        guard let index = elsewhereTurnStart else { return }
        elsewhereTurnStart = nil
        let shown = elsewherePrompt
        elsewherePrompt = nil
        let finished = payload["status"]?.stringValue ?? "complete" == "complete"
        guard finished || shown != nil, let sessionID, let channel = channel() else { return }
        let load = transcriptLoad
        Task { [weak self] in
            let result = try? await channel.call("session.history", params: ["session_id": .string(sessionID)])
            guard let self, transcriptLoad == load,
                let history = try? result?["messages"]?.decode([HistoryMessage].self),
                // Before the reply: you may already have sent the next message from here.
                let reply = history.lastIndex(where: { $0.role == "assistant" }),
                let promptIndex = history[..<reply].lastIndex(where: { $0.role == "user" }),
                // A widget's turn that only rewrote its file has no reply of its own: the one found
                // is the turn before's, whose prompt is already on screen.
                !history[reply...].contains(where: { $0.role == "user" && $0.displayKind == GatewayTurn.hiddenKind })
            else { return }
            let prompt = history[promptIndex]
            if let shown {
                // The same message, or the one shown stays: what you wrote, files and images aside.
                let words = { (text: String) in
                    AttachmentRef.split(text).text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard words(prompt.text ?? "") == words(shown.text) else { return }
                state.replacePrompt(shown.itemID, with: prompt)
                return
            }
            state.insertPrompt(prompt, at: index)
            // A routine the Bot chose not to answer brings no reply to count, so it counts itself.
            if !isVisible, GatewayTurn.news(in: Array(history[promptIndex...])).first == prompt { unreadCount += 1 }
        }
    }

    /// Side answers and background results sent while this device was away. `false` when the
    /// gateway couldn't replay (restarted, or too much happened since).
    private func replay() async -> Bool {
        guard let sessionID, let channel = channel(),
            let result = try? await channel.call(
                "session.events.since",
                params: ["session_id": .string(sessionID), "last_seen": .number(Double(lastSeq))])
        else { return false }
        guard result["truncated"]?.boolValue != true, result["epoch"]?.stringValue == seqEpoch,
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
    private func loseUnansweredWork(_ unanswered: Set<String>) {
        for index in sideQuestions.indices
        where sideQuestions[index].answer == .waiting && unanswered.contains(sideQuestions[index].id) {
            sideQuestions[index].answer = .failed(
                String(localized: "The answer was lost while Usual Bot was offline. Ask again."))
        }
        // A task the gateway never confirmed may not have started at all.
        for task in backgroundTasks where task.id.hasPrefix("local-") && unanswered.contains(task.id) {
            state.addNotice(
                String(
                    localized:
                        "Usual Bot went offline as “\(task.task)” was starting; if no answer comes, start it again."))
        }
        backgroundTasks.removeAll { $0.id.hasPrefix("local-") && unanswered.contains($0.id) }
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
