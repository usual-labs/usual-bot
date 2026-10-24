import Foundation

/// A task handed to a fresh agent that works in the background (Hermes's `/bg`) while the chat
/// goes on. Its answer joins the chat when it's done.
public struct BackgroundTask: Identifiable, Equatable, Sendable, Codable {
    /// The gateway's task ID once it took the task; a local one before.
    public internal(set) var id: String
    public let task: String
}

/// A background task's answer as it joined the chat, kept so it survives reloads of the chat
/// (the gateway's history doesn't have it) and relaunches.
struct BackgroundResult: Equatable, Sendable, Codable {
    let taskID: String
    let task: String
    let result: String
    let date: Date
}

extension ChatThread {
    /// `/bg` (or `/background`) and its words: the background task in a message, if it is one.
    nonisolated static func backgroundTask(in text: String) -> String? {
        words(after: ["/bg", "/background"], in: text)
    }

    /// Starts `text` on a fresh agent in the background. Works while the agent replies, too.
    public func runInBackground(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty, let sessionID, let channel = channel() else { return }
        let localID = "local-\(UUID().uuidString)"
        backgroundTasks.append(BackgroundTask(id: localID, task: text))
        Task {
            do {
                let result = try await channel.call(
                    "prompt.background", params: ["session_id": .string(sessionID), "text": .string(text)])
                guard let taskID = result["task_id"]?.stringValue,
                    let index = backgroundTasks.firstIndex(where: { $0.id == localID })
                else { return }
                backgroundTasks[index].id = taskID
            } catch {
                backgroundTasks.removeAll { $0.id == localID }
                state.addNotice(String(localized: "Couldn't start “\(text)” in the background: \(AppModel.describe(error))"))
            }
        }
    }

    /// `background.complete`: the result joins the chat, or `error: …` becomes a notice.
    func receiveBackgroundResult(_ payload: JSONValue) {
        let taskID = payload["task_id"]?.stringValue ?? ""
        // Delivered twice (live, then from its stored session or a replay): once is enough.
        if !taskID.isEmpty, backgroundResults.contains(where: { $0.taskID == taskID }) { return }
        let text = payload["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // The result can beat the reply that carried its task ID; it then belongs to the oldest
        // task still waiting for one.
        let index =
            backgroundTasks.firstIndex { $0.id == taskID } ?? backgroundTasks.firstIndex { $0.id.hasPrefix("local-") }
        let task = index.map { backgroundTasks.remove(at: $0).task } ?? String(localized: "A background task")
        if text.hasPrefix("error: ") {
            let reason = String(text.dropFirst("error: ".count))
            state.addNotice(String(localized: "The background task “\(task)” failed: \(reason)"))
            backgroundTaskFinished?(task, reason)
            return
        }
        let result = text.nonBlank ?? String(localized: "It finished without an answer.")
        state.addBackgroundResult(task: task, result: result)
        backgroundResults.append(BackgroundResult(taskID: taskID, task: task, result: result, date: .now))
        if backgroundResults.count > 50 { backgroundResults.removeFirst(backgroundResults.count - 50) }
        if !isVisible { unreadCount += 1 }
        backgroundTaskFinished?(task, result)
    }
}
