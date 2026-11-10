import Foundation

/// The goal is Hermes's own: it's kept with the chat on the gateway, judged there after every
/// reply, and carried on there with this app closed. This reads it (`session.control.read`, then
/// `session.control.update`) and changes it only with `session.control`. What a goal does between
/// replies, and why Stop is two calls, is in `docs/agents/canonical-protocol.md`.
extension ChatThread {
    /// How the goal stands, or `nil` with no goal.
    public var goalPhase: GoalPhase? {
        guard let goal else { return nil }
        switch goal.status {
        case .done: return .done
        case .paused: return .stopped
        case .active:
            if state.isRunning || goalTurnComing { return .working }
            return goal.isWaiting ? .waiting : .notRunning
        }
    }

    /// Hermes is about to start the goal's next reply: one is queued behind the reply that just
    /// ended (the gateway's listener), or the last reply is being checked (the dashboard, which
    /// ends a reply before it judges it).
    private var goalTurnComing: Bool { queuesOnGateway ? !goalContinuations.isEmpty : isCheckingGoal }

    /// The goal's buttons work: attached, and not in the middle of another change to it.
    public var canChangeGoal: Bool { canSend && !isChangingGoal }

    // MARK: - Reading it

    /// Reads the goal when the chat attaches. A gateway without goals refuses the call, and then
    /// nothing shows.
    func loadGoal() async {
        guard let sessionID = liveSessionID, let channel = channel() else { return }
        let seen = goalUpdates
        let result = try? await channel.call("session.control.read", params: ["session_id": .string(sessionID)])
        // An update that came while this was read is newer than it.
        guard goalUpdates == seen, liveSessionID == sessionID else { return }
        adoptGoal(result?["control"], live: false)
    }

    /// Takes a control snapshot's goal. `live`: it changed while this app watched, so a goal that
    /// ended by itself is worth an alert.
    func adoptGoal(_ control: JSONValue?, live: Bool) {
        let before = goal
        goalUpdates += 1
        goal = Goal(control?["goal"])
        if goal?.status != .active || goal?.isWaiting == true { isCheckingGoal = false }
        guard live, let goal, before?.status == .active, before?.text == goal.text else { return }
        switch goal.status {
        case .done:
            goalEnded?(goal.text, goal.lastCheck.map { String(localized: "Done: \($0)") } ?? String(localized: "Done"))
        case .paused where goal.stopReason != .byYou:
            goalEnded?(goal.text, goal.stopSentence)
        default:
            break
        }
    }

    /// The goal's own turns in the gateway's list of what's waiting and running (`pending`). The
    /// ones waiting can be taken back when you stop the goal; one that just started gets its line
    /// where its reply begins, as nothing else says why the Bot started talking.
    func adoptGoalTurns(from info: JSONValue?) {
        guard case .array(let rows) = info?["pending"] else { return }
        let turns = rows.filter { GatewayTurn.isGoalAdmission($0["input_id"]?.stringValue) }
        goalContinuations = turns.filter { $0["status"] == "queued" }.compactMap { $0["admission_id"]?.stringValue }
        if let start = elsewhereTurnStart, let text = turns.first(where: { $0["status"] == "started" })?["text"] {
            elsewhereTurnStart = nil
            state.insertPrompt(
                HistoryMessage(role: "user", text: text.stringValue, displayKind: "internal_notification"), at: start)
        }
    }

    /// A reply ended. The dashboard judges it only now, so until the verdict comes the goal still
    /// counts as working; Hermes judges only a reply that finished and said something.
    func goalReplyEnded(_ payload: JSONValue) {
        guard !queuesOnGateway, goal?.status == .active, goal?.isWaiting != true else { return }
        let finished = payload["status"]?.stringValue ?? "complete" == "complete"
        isCheckingGoal = finished && payload["text"]?.stringValue?.nonBlank != nil
    }

    // MARK: - Your actions

    /// Stops the goal: Hermes keeps it but starts nothing more for it, then the reply that's
    /// running is stopped. In that order, because Hermes judges an interrupted reply like any
    /// other and would send the Bot straight on.
    public func stopGoal() {
        guard canChangeGoal, let goal, goal.status == .active else { return }
        #if DEBUG
            if isGoalDemo {
                self.goal?.status = .paused
                self.goal?.pausedReason = "user-paused"
                state.addNotice(String(localized: "You stopped the goal"))
                if state.isRunning { stop() }
                return
            }
        #endif
        guard let sessionID = liveSessionID, let channel = channel() else { return }
        isChangingGoal = true
        Task {
            defer { isChangingGoal = false }
            do {
                _ = try await control("goal.pause", sessionID: sessionID, channel: channel)
            } catch {
                state.addNotice(String(localized: "Couldn't stop the goal: \(AppModel.describe(error))"))
                return
            }
            // Turns Hermes had already queued for it would still run.
            for admission in goalContinuations {
                _ = try? await channel.call(
                    "prompt.cancel", params: ["session_id": .string(sessionID), "admission_id": .string(admission)])
            }
            state.addNotice(String(localized: "You stopped the goal"))
            if state.isRunning { stop() }
        }
    }

    /// Carries on with a goal that stopped or isn't running, with a full set of turns again.
    /// Hermes hands back the message that starts the next reply, for this app to send.
    public func continueGoal() {
        guard canChangeGoal, !state.isRunning, let goal, goal.status != .done else { return }
        #if DEBUG
            if isGoalDemo {
                self.goal?.status = .active
                self.goal?.pausedReason = nil
                self.goal?.turnsUsed = 0
                state.addNotice(GatewayTurn.goalStep)
                state.beginTurn()
                playDemoReply()
                return
            }
        #endif
        guard let sessionID = liveSessionID, let channel = channel() else { return }
        isChangingGoal = true
        Task {
            defer { isChangingGoal = false }
            do {
                let dispatch = try await control("goal.resume", sessionID: sessionID, channel: channel)
                guard let message = dispatch["message"]?.stringValue?.nonBlank else { return }
                state.addNotice(GatewayTurn.goalStep)
                state.beginTurn()
                await submit(message, sessionID: sessionID, channel: channel)
            } catch {
                state.addNotice(String(localized: "Couldn't continue the goal: \(AppModel.describe(error))"))
            }
        }
    }

    /// Removes a goal that's done, stopped or not running. A working one is stopped first.
    public func clearGoal() {
        guard canChangeGoal, goal != nil, goalPhase != .working else { return }
        #if DEBUG
            if isGoalDemo {
                goal = nil
                return
            }
        #endif
        guard let sessionID = liveSessionID, let channel = channel() else { return }
        isChangingGoal = true
        Task {
            defer { isChangingGoal = false }
            do {
                _ = try await control("goal.clear", sessionID: sessionID, channel: channel)
            } catch {
                state.addNotice(String(localized: "Couldn't clear the goal: \(AppModel.describe(error))"))
            }
        }
    }

    /// One `session.control` action. Its answer has the goal as it now stands, and what the
    /// command said (`dispatch`).
    private func control(_ action: String, sessionID: String, channel: JSONRPCChannel) async throws -> JSONValue {
        let result = try await channel.call(
            "session.control", params: ["session_id": .string(sessionID), "action": .string(action)])
        adoptGoal(result["control"], live: false)
        return result["dispatch"] ?? [:]
    }

    // MARK: - Typed commands

    /// `/goal` and `/subgoal` only change the goal's state, so Hermes runs them while a reply is
    /// under way; other commands wait for it to end.
    nonisolated static let goalCommands: Set<String> = ["/goal", "/subgoal"]

    /// Whether `/goal <argument>` controls the goal there is instead of setting a new one
    /// (`is_goal_control` in `hermes_cli/goal_command.py`).
    nonisolated static func controlsGoal(_ argument: String) -> Bool {
        let argument = argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let whole: Set<String> = ["", "clear", "stop", "done"]
        let first: Set<String> = ["status", "show", "pause", "resume", "continue", "unpause", "unwait", "wait", "gate"]
        return whole.contains(argument) || first.contains(String(argument.prefix { !$0.isWhitespace }))
    }

    #if DEBUG
        /// The demo has no gateway to keep a goal, judge it or carry it on.
        var isGoalDemo: Bool { playsDemoReplies && channel() == nil }

        /// `/goal <words>` and its `stop`, `resume` and `clear` in the demo. `false` for anything else.
        func runDemoGoalCommand(_ text: String) -> Bool {
            guard isGoalDemo, text.lowercased().hasPrefix("/goal") else { return false }
            let argument = String(text.dropFirst("/goal".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            switch argument.lowercased() {
            case "pause": stopGoal()
            case "resume", "continue": continueGoal()
            case "clear", "stop", "done": goal = nil
            case "", "status", "show": break
            default:
                guard !state.isRunning else {
                    state.addNotice(Self.goalWhileReplying)
                    return true
                }
                goal = Goal(text: argument)
                state.sendLocally(text)
                playDemoReply()
            }
            return true
        }

        /// A demo reply ended: the goal's turn is counted, and it goes on until its third.
        func continueDemoGoal(after payload: JSONValue) {
            guard isGoalDemo, !state.isRunning, var goal, goal.status == .active, payload["status"] == nil else {
                return
            }
            goal.turnsUsed += 1
            if goal.turnsUsed >= 3 {
                goal.status = .done
                goal.lastCheck = "The reply shows the work finished and checked."
            } else {
                goal.lastCheck = "One more step is left."
            }
            self.goal = goal
            guard goal.status == .active else { return }
            state.addNotice(GatewayTurn.goalStep)
            state.beginTurn()
            playDemoReply()
        }
    #endif

    static var goalWhileReplying: String {
        String(localized: "A reply is running. Set a new goal when it ends, or stop this one first.")
    }
}
