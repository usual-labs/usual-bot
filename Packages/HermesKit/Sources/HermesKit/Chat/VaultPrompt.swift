import Foundation

/// The agent needs something from you for the Hermes vault during a turn. The answer goes straight
/// to the vault or the page; the agent's model never sees it.
public struct VaultPrompt: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The master password that unlocks a password manager for this session.
        case unlock(backend: String, displayName: String)
        /// A login to save for the page the agent is on, and fill at once.
        case saveLogin(origin: String, site: String)
        /// A one-time code you read from your phone, email or app.
        case code(site: String?, hint: String?)
    }

    /// Requests that always get an answer here. Any other answer than `skipped` or what you typed is
    /// taken for your answer: `4404` would put its error text in a password manager or a code field.
    static let methods: Set<String> = ["vault.unlock_prompt", "vault.save_login", "vault.code"]
    /// How the gateway hears "skipped": each caller treats an empty value as declined.
    static let skipped: JSONValue = ["value": ""]

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
        let text = { (key: String) in request.params[key]?.stringValue?.nonBlank }
        switch request.method {
        case "vault.unlock_prompt":
            guard let backend = text("backend") else { return nil }
            kind = .unlock(backend: backend, displayName: text("display_name") ?? backend)
        case "vault.save_login":
            guard let origin = text("origin") else { return nil }
            kind = .saveLogin(origin: origin, site: text("site") ?? origin)
        case "vault.code":
            kind = .code(site: text("site"), hint: text("hint"))
        default:
            return nil
        }
        id = request.id
        self.sessionID = sessionID
    }

    /// The `value` the gateway expects, or `nil` while something is missing: an empty value would
    /// mean you skipped. `identifier` is for logins, which go as JSON.
    func value(secret: String, identifier: String?) -> String? {
        switch kind {
        case .unlock:
            return secret.isEmpty ? nil : secret
        case .code:
            return secret.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank
        case .saveLogin:
            guard !secret.isEmpty, let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank
            else { return nil }
            let login: JSONValue = ["identifier": .string(identifier), "password": .string(secret)]
            return (try? JSONEncoder().encode(login)).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    /// What a notice calls the prompt. Names the site or manager, never an answer.
    var sentNotice: String {
        switch kind {
        case .unlock(_, let name): return String(localized: "You sent the master password for \(name)")
        case .saveLogin(_, let site): return String(localized: "You sent a login for \(site)")
        case .code(let site?, _): return String(localized: "You sent the code for \(site)")
        case .code(nil, _): return String(localized: "You sent the code")
        }
    }

    var skippedNotice: String {
        switch kind {
        case .unlock(_, let name): return String(localized: "You kept \(name) locked")
        case .saveLogin(_, let site): return String(localized: "You didn't save a login for \(site)")
        case .code: return String(localized: "You skipped the code")
        }
    }

    var timedOutNotice: String {
        switch kind {
        case .unlock(_, let name): return String(localized: "Nobody answered in time, so \(name) stayed locked.")
        case .saveLogin(_, let site):
            return String(localized: "Nobody answered in time, so no login was saved for \(site).")
        case .code: return String(localized: "Nobody entered the code in time.")
        }
    }
}
