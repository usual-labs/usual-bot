import Foundation

/// Inline widgets talking back: `window.hermes.send(prompt)` in a widget's page sends the prompt
/// as a hidden turn (`display_kind: "hidden"`), as Hermes's desktop app does. The agent runs and
/// the row is stored, but no chat shows it as a message: the agent answers by rewriting the
/// widget's page, which reads its file again when the turn ends (`turnsEnded`).
extension ChatThread {
    /// Sends a widget's prompt. It answers once the gateway has it, so a widget can say "saved"
    /// only when it was. While a reply runs, it waits in the gateway's queue, shown as "From a
    /// widget"; it's never steered into the reply, which would mix a click into another answer.
    /// The dashboard keeps no queue, so there it's refused. Offline it's refused at once: sent
    /// later, it would answer a click from long before.
    public func sendFromWidget(_ prompt: String) async -> WidgetAck {
        #if DEBUG
            if isDemo, canSend {
                if state.isRunning {
                    queue.append(
                        QueuedMessage(id: UUID().uuidString, text: prompt, admissionID: "demo", isFromWidget: true))
                } else {
                    playDemoWidgetTurn(prompt)
                }
                return .sent
            }
        #endif
        guard canSend, let sessionID = liveSessionID, let channel = channel() else {
            return .undelivered(.offline, String(localized: "Usual Bot isn't connected to your gateway right now."))
        }
        state.noteHidden(prompt)
        if state.isRunning {
            guard queuesOnGateway else {
                return .undelivered(
                    .busy, String(localized: "The agent is still replying. Try again when it's done."))
            }
            let item = QueuedMessage(id: UUID().uuidString, text: prompt, isFromWidget: true)
            queue.append(item)
            if let error = await admit(item) { return .undelivered(.refused, AppModel.describe(error)) }
            return .sent
        }
        var params: [String: JSONValue] = [
            "session_id": .string(sessionID), "text": .string(prompt),
            "display_kind": .string(GatewayTurn.hiddenKind),
        ]
        if queuesOnGateway {
            let id = UUID().uuidString
            sentDirectly.insert(id)
            params["submission_id"] = .string(id)
        }
        state.beginTurn()
        widgetTurnRunning = true
        do {
            _ = try await channel.call("prompt.submit", params: .object(params))
            return .sent
        } catch {
            widgetTurnRunning = false
            state.endTurnLocally()
            return .undelivered(.refused, AppModel.describe(error))
        }
    }

    #if DEBUG
        /// The demo: the agent rewrites the widget's page, with no words in the chat.
        func playDemoWidgetTurn(_ prompt: String) {
            state.beginTurn()
            widgetTurnRunning = true
            let script: [(pause: Double, type: String, payload: JSONValue)] = [
                (
                    0.4, "tool.start",
                    ["tool_id": "widget-1", "name": "terminal", "context": "find /var/log -mtime +14"]
                ),
                (1.0, "tool.complete", ["tool_id": "widget-1"]),
                (0.2, "tool.start", ["tool_id": "widget-2", "name": "write_file", "context": "work/disk.html"]),
                (0.6, "tool.complete", ["tool_id": "widget-2"]),
                (0.2, "message.complete", ["status": "complete"]),
            ]
            Task {
                for step in script {
                    // sleep-ok: the demo's pretend gateway takes its time, as a real one would.
                    try? await Task.sleep(for: .seconds(step.pause))
                    if step.type == "message.complete" { demoWidgetAnswered?(prompt) }
                    apply(GatewayEvent(type: step.type, sessionID: "sample", seq: nil, payload: step.payload))
                }
            }
        }
    #endif
}
