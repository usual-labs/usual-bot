import Foundation

/// The model a chat runs on and how hard it thinks, as the gateway reports it (`session.info`).
public struct ChatModel: Equatable, Sendable {
    public var name: String
    public var provider: String
    /// `nil` while the gateway hasn't said, or when the chat uses the provider's default.
    public var reasoning: ReasoningLevel?

    public init(name: String, provider: String, reasoning: ReasoningLevel? = nil) {
        self.name = name
        self.provider = provider
        self.reasoning = reasoning
    }

    /// From a `session.info` payload, or the `info` a resume or create returns.
    init?(info: JSONValue?) {
        guard let info, let name = info["model"]?.stringValue?.nonBlank else { return nil }
        self.init(
            name: name, provider: info["provider"]?.stringValue ?? "",
            reasoning: info["reasoning_effort"]?.stringValue.flatMap(ReasoningLevel.init(rawValue:)))
    }
}

/// How hard the agent thinks before answering: Hermes's levels, lowest first, and off.
public enum ReasoningLevel: String, CaseIterable, Sendable {
    case off = "none"
    case minimal, low, medium, high, xhigh, max, ultra
}

/// One provider in the gateway's model catalog (`model.options`), with the models it offers.
public struct ModelProvider: Identifiable, Equatable, Sendable {
    /// What `config.set` takes after `--provider`.
    public let slug: String
    public let name: String
    /// The models to offer: an aggregator's shortlist when it has one, else all of them.
    public let models: [String]
    /// Models whose catalog entry says they can't take a reasoning level.
    let withoutReasoning: Set<String>

    public var id: String { slug }

    /// Whether `model` takes a reasoning level. Hermes assumes so when its catalog is silent.
    public func reasons(_ model: String) -> Bool { !withoutReasoning.contains(model) }

    init?(row: JSONValue) {
        guard let slug = row["slug"]?.stringValue?.nonBlank else { return nil }
        let all = Self.strings(row["models"])
        let featured = Self.strings(row["featured_models"])
        guard !all.isEmpty else { return nil }
        self.slug = slug
        name = row["name"]?.stringValue?.nonBlank ?? slug
        models = featured.isEmpty ? all : featured
        var without: Set<String> = []
        if case .object(let capabilities) = row["capabilities"] {
            for (model, entry) in capabilities where entry["reasoning"]?.boolValue == false { without.insert(model) }
        }
        withoutReasoning = without
    }

    init(slug: String, name: String, models: [String], withoutReasoning: Set<String> = []) {
        self.slug = slug
        self.name = name
        self.models = models
        self.withoutReasoning = withoutReasoning
    }

    /// Model IDs are plain strings on current gateways and `{id, name}` objects on older ones.
    private static func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let entries) = value else { return [] }
        return entries.compactMap { $0.stringValue ?? $0["id"]?.stringValue }
    }
}

/// What came of asking to switch a chat's model.
public enum ModelSwitch: Equatable, Sendable {
    /// The chat runs on it now.
    case switched
    /// A reply is being written; the switch happens when the next message starts.
    case next
    /// The gateway wants a yes first (an expensive model, say); ask again with `confirmed`.
    case needsConfirmation(String)
    case failed(String)
}

extension ChatThread {
    /// Loads the models this chat can switch to. Keeps the old list if the gateway can't answer.
    public func loadModels() async {
        guard let sessionID, let channel = channel() else { return }
        guard
            let result = try? await channel.call(
                "model.options", params: ["session_id": .string(sessionID)], timeout: .seconds(20)),
            case .array(let rows) = result["providers"]
        else { return }
        modelProviders = rows.compactMap(ModelProvider.init(row:))
    }

    /// Switches this chat (only this chat: the agent's default stays) to `name` from `provider`.
    public func setModel(_ name: String, provider: String, confirmed: Bool = false) async -> ModelSwitch {
        guard let sessionID, let channel = channel() else {
            return .failed(String(localized: "The agent isn't connected."))
        }
        var params: [String: JSONValue] = [
            "session_id": .string(sessionID), "key": "model",
            "value": .string("\(name) --provider \(provider) --session"),
        ]
        if confirmed { params["confirm_expensive_model"] = true }
        do {
            let result = try await channel.call("config.set", params: .object(params), timeout: .seconds(45))
            if result["confirm_required"]?.boolValue == true {
                return .needsConfirmation(
                    result["confirm_message"]?.stringValue?.nonBlank
                        ?? String(localized: "\(name) costs more than the model this chat uses."))
            }
            // The gateway follows up with `session.info`; show the pick until then.
            model = ChatModel(name: name, provider: provider, reasoning: model?.reasoning)
            if let warning = result["warning"]?.stringValue?.nonBlank { state.addNotice(warning) }
            if result["deferred"]?.boolValue == true {
                state.addNotice(String(localized: "\(name) takes over from your next message."))
                return .next
            }
            return .switched
        } catch {
            return .failed(AppModel.describe(error))
        }
    }

    /// Sets how hard this chat's agent thinks. Shows at once; a refusal puts the old level back.
    public func setReasoning(_ level: ReasoningLevel) {
        guard let sessionID, let channel = channel() else { return }
        let before = model
        model?.reasoning = level
        Task {
            do {
                _ = try await channel.call(
                    "config.set",
                    params: ["session_id": .string(sessionID), "key": "reasoning", "value": .string(level.rawValue)])
            } catch {
                model = before
                state.addNotice(String(localized: "Couldn't change thinking: \(AppModel.describe(error))"))
            }
        }
    }
}
