import Foundation

/// The gateway asking for something typed into a masked field and waiting for it: a secret a skill
/// needs, or the sudo password for a command. The answer goes straight back; the app keeps no copy.
public struct SecretPrompt: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A value the gateway saves as the environment variable `name`. `message` is its own wording.
        case secret(name: String, message: String)
        /// Redacted by the gateway before it is sent.
        case sudo(command: String)
    }

    /// The server requests this prompt answers.
    static let methods: Set<String> = ["secret", "sudo"]

    /// The server request ID the answer goes back to.
    public let id: String
    public let sessionID: String
    public let kind: Kind

    init(id: String, sessionID: String, kind: Kind) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
    }

    init?(_ request: ServerRequest) {
        guard let sessionID = request.sessionID else { return nil }
        switch request.method {
        case "secret":
            guard let name = request.params["env_var"]?.stringValue else { return nil }
            kind = .secret(name: name, message: request.params["prompt"]?.stringValue ?? "")
        case "sudo":
            kind = .sudo(command: request.params["command"]?.stringValue ?? "")
        default:
            return nil
        }
        id = request.id
        self.sessionID = sessionID
    }
}
