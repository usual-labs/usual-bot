import Foundation

/// A skill or command the `/` menu offers.
public struct SlashCommand: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Loads one of the agent's skills for the message after it.
        case skill
        /// A quick, plugin or built-in command.
        case command
    }

    /// With its slash, e.g. `/web-research`.
    public let name: String
    public let description: String
    public let kind: Kind

    public var id: String { name }

    public init(name: String, description: String, kind: Kind) {
        self.name = name
        self.description = description
        self.kind = kind
    }
}

extension ChatThread {
    /// Hermes built-ins left out of the menu although the official app offers them: they would
    /// switch, rename or split the agent's one chat (which the app finds by its title), or style a
    /// terminal.
    nonisolated static let notInMessenger: Set<String> = [
        "/new", "/resume", "/sessions", "/branch", "/title", "/handoff", "/import", "/profile",
        "/skin", "/pet", "/hatch", "/palette", "/timestamps", "/suggestions",
    ]

    /// Loads the `/` menu: the agent's skills, its quick and plugin commands, and Hermes's
    /// built-ins that make sense here. Keeps the old list if the gateway can't answer.
    public func loadCommands() async {
        guard let sessionID, let channel = channel() else { return }
        guard let catalog = try? await channel.call("commands.catalog", params: ["session_id": .string(sessionID)])
        else { return }
        commands = Self.commands(in: catalog)
    }

    nonisolated static func commands(in catalog: JSONValue) -> [SlashCommand] {
        guard case .array(let pairs) = catalog["pairs"] else { return [] }
        let skills: Set<String> = {
            guard case .object(let skills) = catalog["skills"] else { return [] }
            return Set(skills.keys)
        }()
        // `commands` describes the registry's built-ins: those with a `desktop` reason are
        // terminal-only, settings or advanced in the official app, so they stay out here too.
        let registry: [String: JSONValue] = {
            guard case .object(let commands) = catalog["commands"] else { return [:] }
            return commands
        }()
        var seen: Set<String> = []
        return pairs.compactMap { pair -> SlashCommand? in
            guard case .array(let fields) = pair, let name = fields.first?.stringValue, name.hasPrefix("/"),
                seen.insert(name).inserted
            else { return nil }
            let description = fields.dropFirst().first?.stringValue ?? ""
            if skills.contains(name) { return SlashCommand(name: name, description: description, kind: .skill) }
            if let meta = registry[name] {
                guard meta["desktop"]?.stringValue == nil, !notInMessenger.contains(name) else { return nil }
            }
            return SlashCommand(name: name, description: description, kind: .command)
        }
    }

    /// The menu command a message starts with, if any.
    func command(in text: String) -> SlashCommand? {
        guard text.hasPrefix("/") else { return nil }
        let name = String(text.prefix { !$0.isWhitespace })
        return commands.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Runs a command through `command.dispatch` and does what it answers: send a message (a
    /// skill), show output, put text back in the message box, or run the command it aliases.
    func run(_ command: SlashCommand, text: String, sessionID: String, channel: JSONRPCChannel, depth: Int = 0)
        async
    {
        let argument = String(text.dropFirst(command.name.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await channel.call(
                "command.dispatch",
                params: [
                    "session_id": .string(sessionID), "name": .string(String(command.name.dropFirst())),
                    "arg": .string(argument),
                ])
            switch result["type"]?.stringValue {
            case "skill", "send":
                guard let message = result["message"]?.stringValue, !message.isEmpty else { break }
                // The bubble shows what you typed (or the gateway's short form), not the skill's text.
                state.sendLocally(result["display"]?.stringValue?.nonBlank ?? text)
                if let notice = result["notice"]?.stringValue?.nonBlank { state.addNotice(notice) }
                await submit(message, sessionID: sessionID, channel: channel)
            case "prefill":
                prefill = result["message"]?.stringValue
                if let notice = result["notice"]?.stringValue?.nonBlank { state.addNotice(notice) }
            case "alias":
                guard depth < 3, let target = result["target"]?.stringValue?.nonBlank else { break }
                let aliased = SlashCommand(name: "/" + target.trimmingPrefix("/"), description: "", kind: .command)
                await run(
                    aliased, text: aliased.name + (argument.isEmpty ? "" : " " + argument), sessionID: sessionID,
                    channel: channel, depth: depth + 1)
            default:
                // `exec` and `plugin`: output to read, no turn.
                state.showCommand(text)
                if let output = result["output"]?.stringValue?.nonBlank {
                    state.addOutput(output)
                } else if let notice = result["notice"]?.stringValue?.nonBlank {
                    state.addNotice(notice)
                }
            }
        } catch GatewayError.rpc(code: 4018, let message) where message.hasPrefix("not a quick/plugin") {
            // Not a quick, plugin or skill command: a Hermes built-in, which runs as Hermes's own
            // slash command (on the live chat where the gateway applies it there).
            await runBuiltin(command, text: text, sessionID: sessionID, channel: channel)
        } catch {
            state.addNotice(String(localized: "\(command.name) didn't run: \(AppModel.describe(error))"))
        }
    }

    private func runBuiltin(_ command: SlashCommand, text: String, sessionID: String, channel: JSONRPCChannel) async {
        do {
            let result = try await channel.call(
                "slash.exec", params: ["session_id": .string(sessionID), "command": .string(text)],
                timeout: .seconds(120))
            if result["type"]?.stringValue == "send", let message = result["message"]?.stringValue?.nonBlank {
                // A command that composed the next message (/prompt): send it as yours.
                state.sendLocally(message)
                await submit(message, sessionID: sessionID, channel: channel)
                return
            }
            state.showCommand(text)
            state.addOutput(result["output"]?.stringValue?.nonBlank ?? String(localized: "(no output)"))
            if let warning = result["warning"]?.stringValue?.nonBlank { state.addNotice(warning) }
        } catch {
            state.addNotice(String(localized: "\(command.name) didn't run: \(AppModel.describe(error))"))
        }
    }
}
