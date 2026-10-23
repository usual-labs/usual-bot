import Foundation

/// The agent's clarify tool asking you one to five questions and waiting for the answers.
public struct ClarifyPrompt: Identifiable, Equatable, Sendable {
    public struct Question: Identifiable, Equatable, Sendable {
        public let id: String
        public let text: String
        /// Suggested answers. You can always type your own instead.
        public let choices: [String]
        /// Several of `choices` may be picked.
        public let allowsMultiple: Bool
    }

    /// The server request ID the answers go back to.
    public let id: String
    public let sessionID: String
    public let questions: [Question]

    init?(_ request: ServerRequest) {
        guard request.method == "clarify", let sessionID = request.sessionID,
            case .array(let raw) = request.params["questions"]
        else { return nil }
        let questions = raw.compactMap { item -> Question? in
            guard let id = item["qid"]?.stringValue, let text = item["question"]?.stringValue else { return nil }
            var choices: [String] = []
            if case .array(let offered) = item["choices"] { choices = offered.compactMap(\.stringValue) }
            return Question(
                id: id, text: text, choices: choices,
                allowsMultiple: item["multi_select"]?.boolValue == true && !choices.isEmpty)
        }
        guard !questions.isEmpty else { return nil }
        id = request.id
        self.sessionID = sessionID
        self.questions = questions
    }

    /// The wire form of one answer: the text itself, or a JSON list for multi-select questions.
    static func encode(_ picked: [String], for question: Question) -> String {
        guard question.allowsMultiple else { return picked.first ?? "" }
        let data = (try? JSONEncoder().encode(picked)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
