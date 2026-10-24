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

    /// `/reasoning [level] [--global]`: shows this chat's thinking level, or sets it the way the
    /// model menu does (or, with `--global`, as the agent's default). Hermes's own `/reasoning`
    /// would change its command worker, not this chat.
    func runReasoningCommand(_ text: String) {
        guard let sessionID, let channel = channel() else { return }
        state.showCommand(text)
        let words = (Self.words(after: ["/reasoning"], in: text) ?? "").split(separator: " ").map(String.init)
        let global = words.contains { ["--global", "-g", "global"].contains($0.lowercased()) }
        let value = words.filter { !["--global", "-g", "global", "--session", "-s", "session"].contains($0.lowercased()) }
            .joined(separator: " ")
        guard !value.isEmpty else {
            let level = model?.reasoning.map(\.rawValue) ?? String(localized: "the model's default")
            state.addNotice(String(localized: "Thinking in this chat: \(level)"))
            return
        }
        Task {
            var params: [String: JSONValue] = [
                "session_id": .string(sessionID), "key": "reasoning", "value": .string(value),
            ]
            if global {
                // The agent's own config; without `profile` the gateway's main profile would change.
                params["scope"] = "global"
                params["profile"] = .string(contactID)
            }
            do {
                let result = try await channel.call("config.set", params: .object(params))
                let applied = result["value"]?.stringValue ?? value
                if let level = ReasoningLevel(rawValue: applied.lowercased()) { model?.reasoning = level }
                state.addNotice(
                    global
                        ? String(localized: "Thinking set to \(applied) for this agent")
                        : String(localized: "Thinking set to \(applied) in this chat"))
            } catch {
                state.addNotice(String(localized: "/reasoning didn't run: \(AppModel.describe(error))"))
            }
        }
    }

    /// Makes this chat's model the agent's default, as the official Bots editor does: its other
    /// chats, routines and rooms use it from then on. A pricier model asks first, as switching does.
    public func makeModelDefault(confirmed: Bool = false) async -> ModelSwitch {
        guard let model, let channel = channel() else {
            return .failed(String(localized: "The agent isn't connected."))
        }
        var params: [String: JSONValue] = [
            "name": .string(contactID), "model": .string(model.name), "provider": .string(model.provider),
        ]
        if confirmed { params["confirm_expensive_model"] = true }
        do {
            let result = try await channel.call("profiles.configure", params: .object(params))
            if result["confirm_required"]?.boolValue == true {
                return .needsConfirmation(
                    result["confirm_message"]?.stringValue?.nonBlank
                        ?? String(localized: "\(model.name) costs more than the agent's default model."))
            }
            guard result["applied"]?["model"]?.boolValue != false else {
                return .failed(String(localized: "The gateway couldn't save the agent's settings."))
            }
            state.addNotice(String(localized: "\(model.name) is now this agent's default model."))
            return .switched
        } catch {
            return .failed(AppModel.describe(error))
        }
    }

    /// Makes this chat's thinking level the agent's default (`agent.reasoning_effort` in its config).
    public func makeReasoningDefault() async {
        guard let level = model?.reasoning, let sessionID, let channel = channel() else { return }
        do {
            _ = try await channel.call(
                "config.set",
                params: [
                    "session_id": .string(sessionID), "key": "reasoning", "value": .string(level.rawValue),
                    "scope": "global", "profile": .string(contactID),
                ])
            state.addNotice(String(localized: "This agent now thinks at \(level.rawValue) by default."))
        } catch {
            state.addNotice(String(localized: "Couldn't change the default thinking: \(AppModel.describe(error))"))
        }
    }
}
