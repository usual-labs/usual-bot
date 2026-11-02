import Foundation

/// An MCP server in an agent's profile, which the app calls an app. The gateway sends env values
/// masked; only their names are kept here.
public struct MCPServer: Identifiable, Equatable, Sendable, Decodable {
    public let name: String
    /// Set for a server reached over the web.
    public let url: String?
    /// Set for a server the gateway runs as a program.
    public let command: String?
    public let args: [String]
    /// The env values set for it, by name only.
    public let envNames: [String]
    /// `oauth`, `header`, or nil for none.
    public let auth: String?
    public var enabled: Bool
    /// The plugin that provides it. Such a server can't be changed or removed here.
    public let plugin: String?

    public var id: String { name }
    public var isFromPlugin: Bool { plugin != nil }
    /// Signs in through the provider's web page.
    public var usesSignIn: Bool { auth == "oauth" }

    /// Where it runs, in short: the web address's host, or the program and its first argument.
    public var location: String {
        if let url { return URL(string: url)?.host() ?? url }
        guard let command else { return "" }
        let program = command.split(separator: "/").last.map(String.init) ?? command
        let first = args.first { !$0.hasPrefix("-") }
        return [program, first].compactMap { $0 }.joined(separator: " ")
    }

    public init(
        name: String, url: String? = nil, command: String? = nil, args: [String] = [], envNames: [String] = [],
        auth: String? = nil, enabled: Bool = true, plugin: String? = nil
    ) {
        self.name = name
        self.url = url
        self.command = command
        self.args = args
        self.envNames = envNames
        self.auth = auth
        self.enabled = enabled
        self.plugin = plugin
    }

    private enum CodingKeys: String, CodingKey {
        case name, url, command, args, env, auth, enabled, source, plugin
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url).flatMap { $0.isEmpty ? nil : $0 }
        command = try container.decodeIfPresent(String.self, forKey: .command).flatMap { $0.isEmpty ? nil : $0 }
        args = (try? container.decodeIfPresent([String].self, forKey: .args)) ?? []
        // Values come masked, or empty when unset. Keep the names of the set ones and drop the rest.
        let env = (try? container.decodeIfPresent([String: String].self, forKey: .env)) ?? [:]
        envNames = env.filter { !$0.value.isEmpty }.keys.sorted()
        auth = try container.decodeIfPresent(String.self, forKey: .auth)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let source = try container.decodeIfPresent(String.self, forKey: .source)
        let plugin = try container.decodeIfPresent(String.self, forKey: .plugin)
        self.plugin = source == "plugin" ? (plugin ?? "") : nil
    }
}

/// A tool a server offers, as a connection test lists it.
public struct MCPTool: Identifiable, Equatable, Sendable, Decodable {
    public let name: String
    public let description: String?

    public var id: String { name }

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// A server from Hermes's catalog of reviewed MCP servers.
public struct MCPCatalogEntry: Identifiable, Equatable, Sendable, Decodable {
    /// A value the server needs before it can run, like an API key.
    public struct Key: Equatable, Sendable, Decodable, Identifiable {
        public let name: String
        public let prompt: String?
        public let required: Bool

        public var id: String { name }

        public init(name: String, prompt: String? = nil, required: Bool = true) {
            self.name = name
            self.prompt = prompt
            self.required = required
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
            required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? true
        }

        private enum CodingKeys: String, CodingKey { case name, prompt, required }
    }

    public let name: String
    public let description: String
    /// `oauth`, `env`, `none` and so on, as the catalog says.
    public let authType: String
    public let requiredEnv: [Key]
    public let url: String?
    public let command: String?
    /// The gateway fetches and builds it first, which takes a while.
    public let needsInstall: Bool
    public let installed: Bool

    public var id: String { name }
    public var usesSignIn: Bool { authType == "oauth" }

    public init(
        name: String, description: String, authType: String = "none", requiredEnv: [Key] = [], url: String? = nil,
        command: String? = nil, needsInstall: Bool = false, installed: Bool = false
    ) {
        self.name = name
        self.description = description
        self.authType = authType
        self.requiredEnv = requiredEnv
        self.url = url
        self.command = command
        self.needsInstall = needsInstall
        self.installed = installed
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, authType, requiredEnv, url, command, needsInstall, installed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        authType = try container.decodeIfPresent(String.self, forKey: .authType) ?? "none"
        requiredEnv = (try? container.decodeIfPresent([Key].self, forKey: .requiredEnv)) ?? []
        url = try container.decodeIfPresent(String.self, forKey: .url)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        needsInstall = try container.decodeIfPresent(Bool.self, forKey: .needsInstall) ?? false
        installed = try container.decodeIfPresent(Bool.self, forKey: .installed) ?? false
    }
}

/// A server you describe yourself: a web address, or a program the gateway runs.
public struct MCPServerDraft: Sendable, Equatable {
    public enum Kind: Sendable, Hashable { case web, program }
    public enum Auth: Sendable, Hashable { case none, token, signIn }

    public var name = ""
    public var kind = Kind.web
    public var url = ""
    public var command = ""
    /// Separated by spaces; quotes keep spaces inside one.
    public var arguments = ""
    public var auth = Auth.none
    public var token = ""

    public init() {}

    public var isComplete: Bool {
        guard !trimmed(name).isEmpty else { return false }
        switch kind {
        case .web:
            guard let url = URL(string: trimmed(url)), ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else { return false }
            return auth != .token || !trimmed(token).isEmpty
        case .program:
            return !trimmed(command).isEmpty
        }
    }

    /// It carries a token, which mustn't cross the network unencrypted without your say-so.
    public var hasSecret: Bool { kind == .web && auth == .token && !trimmed(token).isEmpty }

    /// What the gateway's add route takes. The token only ever goes there.
    var body: Body {
        switch kind {
        case .web:
            Body(
                name: trimmed(name), url: trimmed(url), command: nil, args: [],
                auth: auth == .token ? "header" : auth == .signIn ? "oauth" : "none",
                bearerToken: auth == .token ? trimmed(token) : nil)
        case .program:
            Body(
                name: trimmed(name), url: nil, command: trimmed(command), args: Self.split(arguments), auth: "none",
                bearerToken: nil)
        }
    }

    struct Body: Encodable, Sendable {
        let name: String
        let url: String?
        let command: String?
        let args: [String]
        let auth: String
        let bearerToken: String?
        var profile: String?
    }

    /// Splits on spaces, keeping what's inside double quotes together.
    static func split(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quoted = false
        var started = false
        for character in text {
            if character == "\"" {
                quoted.toggle()
                started = true
            } else if character.isWhitespace && !quoted {
                if started { words.append(current) }
                current = ""
                started = false
            } else {
                current.append(character)
                started = true
            }
        }
        if started { words.append(current) }
        return words
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
