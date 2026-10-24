import Foundation

/// A quick question about the chat, answered on the side: the agent keeps working and the
/// question never enters its history (Hermes's `/btw`). Shown until you dismiss it, never cached.
public struct SideQuestion: Identifiable, Equatable, Sendable {
    public enum Answer: Equatable, Sendable {
        case waiting
        case answered(String)
        case failed(String)
    }

    /// The gateway's task ID once it took the question; a local one before.
    public internal(set) var id: String
    public let question: String
    public internal(set) var answer: Answer
}

extension ChatThread {
    /// `/btw` and its words: the side question in a message, if it is one.
    nonisolated static func sideQuestion(in text: String) -> String? { words(after: ["/btw"], in: text) }

    /// The words after one of `commands` that starts `text`, if there are any.
    nonisolated static func words(after commands: Set<String>, in text: String) -> String? {
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, commands.contains(first.lowercased()) else { return nil }
        return parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines).nonBlank : nil
    }

    /// Asks `text` on the side. Works while the agent replies, too.
    public func askOnTheSide(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty, let sessionID, let channel = channel() else { return }
        let localID = "local-\(UUID().uuidString)"
        sideQuestions.append(SideQuestion(id: localID, question: text, answer: .waiting))
        Task {
            do {
                let result = try await channel.call(
                    "prompt.btw", params: ["session_id": .string(sessionID), "text": .string(text)])
                guard let taskID = result["task_id"]?.stringValue,
                    let index = sideQuestions.firstIndex(where: { $0.id == localID })
                else { return }
                sideQuestions[index].id = taskID
            } catch {
                update(localID) { $0.answer = .failed(AppModel.describe(error)) }
            }
        }
    }

    public func dismiss(_ question: SideQuestion) {
        sideQuestions.removeAll { $0.id == question.id }
    }

    /// `btw.complete`: the answer, or `error: …` when the side agent failed.
    func receiveSideAnswer(_ payload: JSONValue) {
        let text = payload["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let answer: SideQuestion.Answer =
            text.hasPrefix("error: ")
            ? .failed(String(text.dropFirst("error: ".count)))
            : .answered(text.nonBlank ?? String(localized: "No answer."))
        let taskID = payload["task_id"]?.stringValue ?? ""
        let question = payload["question"]?.stringValue ?? ""
        if sideQuestions.contains(where: { $0.id == taskID }) {
            update(taskID) { $0.answer = answer }
        } else if let waiting = sideQuestions.first(where: {
            $0.id.hasPrefix("local-") && $0.question == question && $0.answer == .waiting
        }) {
            // The answer beat the reply that carried its task ID.
            update(waiting.id) {
                $0.id = taskID
                $0.answer = answer
            }
        } else if !question.isEmpty {
            // Asked from another app attached to this chat.
            sideQuestions.append(SideQuestion(id: taskID, question: question, answer: answer))
        }
    }

    private func update(_ id: String, _ change: (inout SideQuestion) -> Void) {
        guard let index = sideQuestions.firstIndex(where: { $0.id == id }) else { return }
        change(&sideQuestions[index])
    }
}
