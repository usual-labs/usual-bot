import Foundation

/// The gateway asking whether the agent may run a dangerous command.
public struct ApprovalPrompt: Identifiable, Equatable, Sendable {
    public enum Choice: String, CaseIterable, Sendable {
        /// Run it this time.
        case once
        /// Allow commands like it for the rest of this chat.
        case session
        /// Allow commands like it from now on.
        case always
        case deny
    }

    /// The server request ID the answer goes back to.
    public let id: String
    public let sessionID: String
    /// Redacted by the gateway before it is sent.
    public let command: String
    public let description: String
    /// What the gateway offers, in its order. `deny` is always possible.
    public let choices: [Choice]

    init?(_ request: ServerRequest) {
        guard request.method == "approval", let sessionID = request.sessionID else { return nil }
        id = request.id
        self.sessionID = sessionID
        command = request.params["command"]?.stringValue ?? ""
        description = request.params["description"]?.stringValue ?? ""
        var choices: [Choice] = []
        if case .array(let offered) = request.params["choices"] {
            choices = offered.compactMap { $0.stringValue.flatMap(Choice.init(rawValue:)) }
        }
        if choices.isEmpty { choices = [.once] }
        if !choices.contains(.deny) { choices.append(.deny) }
        self.choices = choices
    }
}
