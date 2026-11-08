import HermesKit
import SwiftUI

/// The commands that set up Usual's gateway plugins, and the same steps as a request to a Bot.
enum SetupCommands {
    enum Plugin {
        case push, browser

        var folder: String {
            switch self {
            case .push: "hermes-push"
            case .browser: "hermes-browser"
            }
        }

        var name: String {
            switch self {
            case .push: "usual-push"
            case .browser: "usual-browser"
            }
        }
    }

    static let clone = "git clone https://github.com/usual-labs/usual-bot"
    static let restart = "hermes gateway restart"

    static func script(_ plugin: Plugin) -> String { "sh usual-bot/Integrations/\(plugin.folder)/install.sh" }

    static func install(_ plugin: Plugin) -> String { [clone, script(plugin), restart].joined(separator: "\n") }

    /// Turns real-profile browsing on for `profile`, adds the plugin to it and restarts. The main
    /// folder's profile takes no `-p`.
    static func turnOnBrowser(profile: String) -> String {
        [configSet(profile: profile), script(.browser), restart].joined(separator: "\n")
    }

    static func askInstall(_ plugin: Plugin) -> String {
        request(
            "Please install the \(plugin.name) plugin for Usual Bot on this gateway.",
            steps: [cloneStep, "Run `\(script(plugin))` and show me what it printed."])
    }

    static func askTurnOnBrowser(profile: String, name: String) -> String {
        request(
            "Please set up the Usual Bot browser view for \(name) (Hermes profile `\(profile)`) on this gateway.",
            steps: [
                "Run `\(configSet(profile: profile))`, and check that this profile’s browser runs headless.",
                cloneStep,
                "Run `\(script(.browser))` and show me what it printed.",
            ])
    }

    private static let sandboxWarning =
        "Run these on the computer the gateway runs on. If your terminal is in a Docker or SSH sandbox, stop and tell me instead."

    private static let cloneStep =
        "If there’s no `usual-bot` folder in the current directory yet, run `\(clone)`."

    private static func configSet(profile: String) -> String {
        let hermes = profile == "default" ? "hermes" : "hermes -p \(profile)"
        return "\(hermes) config set browser.use_real_profile true"
    }

    /// The Bot runs it with its own terminal, which has to be the gateway's computer, and restarts
    /// last: the restart drops this chat for a moment.
    private static func request(_ ask: String, steps: [String]) -> String {
        let all = steps + ["Last, run `\(restart)`. This chat will drop for a moment and come back."]
        let numbered = all.enumerated().map { "\($0.offset + 1). \($0.element)" }
        let lead = [ask, sandboxWarning]
        return (lead + numbered).joined(separator: "\n\n")
    }
}

/// A step: what to do, and its commands, selectable, with Copy and Ask a Bot.
struct SetupStep: View {
    let text: LocalizedStringKey
    let command: String
    let message: String
    let bots: [Contact]
    let ask: (Contact, String) -> Void

    init(
        _ text: LocalizedStringKey, command: String, message: String, bots: [Contact],
        ask: @escaping (Contact, String) -> Void
    ) {
        self.text = text
        self.command = command
        self.message = message
        self.bots = bots
        self.ask = ask
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 8) {
                AskBotMenu(title: "Ask a Bot", message: message, bots: bots, ask: ask)
                CopyButton(command: command, label: "Copy")
            }
        }
        .padding(.vertical, 4)
    }
}

/// A Bot's Set Up: ask a Bot, or copy the commands.
struct SetupMenu: View {
    let command: String
    let message: String
    let bots: [Contact]
    let ask: (Contact, String) -> Void

    var body: some View {
        Menu("Set Up") {
            Section("Ask a Bot") { AskBotItems(message: message, bots: bots, ask: ask) }
            Button("Copy Commands") { Clipboard.copy(command) }
        }
        .fixedSize()
        .controlSize(.small)
        .clickable()
    }
}

private struct AskBotMenu: View {
    let title: LocalizedStringKey
    let message: String
    let bots: [Contact]
    let ask: (Contact, String) -> Void

    var body: some View {
        Menu(title) { AskBotItems(message: message, bots: bots, ask: ask) }
            .fixedSize()
            .controlSize(.small)
            .clickable()
            .disabled(bots.isEmpty)
    }
}

private struct AskBotItems: View {
    let message: String
    let bots: [Contact]
    let ask: (Contact, String) -> Void

    var body: some View {
        ForEach(bots) { bot in
            Button(bot.name) { ask(bot, message) }
        }
    }
}

private struct CopyButton: View {
    let command: String
    let label: LocalizedStringKey
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : label) {
            Clipboard.copy(command)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
        .buttonStyle(.clickable(.bordered))
        .controlSize(.small)
        .help(Text(command))
    }
}
