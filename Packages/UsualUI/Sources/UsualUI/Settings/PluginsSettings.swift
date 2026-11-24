import HermesKit
import SwiftUI

/// The Plugins sheet, from the Mac sidebar's footer: Usual's gateway plugins and a Bot's computer,
/// what each needs on the gateway, and which Bots have them now. Setup happens where the gateway
/// runs: each step offers its commands to copy, or Ask a Bot, which opens that Bot's chat with the
/// request typed in its box for you to send. The app itself changes nothing on the gateway.
struct PluginsSettings: View {
    let model: AppModel
    /// Opens `bot`'s chat with `message` in its box, unsent.
    let ask: (Contact, String) -> Void

    var body: some View {
        if model.isSignedIn {
            let bots = model.contacts.filter { $0.kind == .agent }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            PluginSetup(model: model, bots: bots, ask: ask)
            BrowserSetup(model: model, bots: bots, ask: ask)
            ComputerSetup(model: model, bots: bots)
            Section {
                Button("Check Again") { Task { await refresh(bots) } }
                    .clickable()
            } footer: {
                Text(
                    "Ask a Bot opens its chat with the request typed in, for you to read and send. It runs the commands with its own terminal, so pick a Bot that runs on the gateway’s computer, not in a Docker or SSH sandbox."
                )
            }
            .task(id: bots.map(\.id)) { await refresh(bots) }
        } else {
            Section { Text("You’re not connected to a gateway. Sign in from the main window.") }
        }
    }

    private func refresh(_ bots: [Contact]) async {
        await withTaskGroup(of: Void.self) { group in
            let push = model.push
            group.addTask { await push.refresh() }
            for bot in bots {
                let browser = model.browser(for: bot)
                let screen = model.screen(for: bot)
                group.addTask { await browser.refresh() }
                group.addTask { await screen.refresh() }
            }
        }
    }
}

/// The `usual-bot` plugin (`Integrations/usual-bot`): installed, out of date or missing. Install
/// and Update go through Hermes's own installer, into every Bot, after you say yes to what
/// Hermes's check found; the commands are there for a gateway that refuses.
private struct PluginSetup: View {
    let model: AppModel
    let bots: [Contact]
    let ask: (Contact, String) -> Void

    @State private var isConfirming = false
    @State private var isInstalling = false
    @State private var problem: String?
    @State private var needsRestart = false

    private var push: PushSettings { model.push }

    var body: some View {
        Section {
            LabeledContent("usual-bot plugin") {
                if isInstalling {
                    ProgressView().controlSize(.small)
                } else {
                    status
                }
            }
            if push.phase == .notInstalled || push.needsUpdate {
                Button(push.needsUpdate ? "Update in Every Bot…" : "Install in Every Bot…") { isConfirming = true }
                    .disabled(isInstalling)
                    .clickable()
                    .confirmationDialog(
                        push.needsUpdate ? "Update the plugin in every Bot?" : "Install the plugin in every Bot?",
                        isPresented: $isConfirming, titleVisibility: .visible
                    ) {
                        Button(push.needsUpdate ? "Update" : "Install") { install() }
                    } message: {
                        Text(
                            "Hermes downloads it from Usual Bot’s GitHub and installs it into each of your Bots. Hermes checks plugins first and marks this one “caution”: it reads your browser’s version, and its notifications mention sudo when a Bot asks for the password. Choosing \(push.needsUpdate ? "Update" : "Install") accepts that."
                        )
                    }
                if let problem {
                    Text(problem).foregroundStyle(Theme.danger)
                }
                SetupStep(
                    "Or, on the computer your gateway runs on, install it, then restart the gateway:",
                    command: SetupCommands.install, message: SetupCommands.askInstall, bots: bots, ask: ask)
            }
            if needsRestart {
                Text("Restart your gateway to finish: hermes gateway restart")
                    .foregroundStyle(Theme.needsYouInk)
            }
        } header: {
            Text("Usual Bot Plugin")
        } footer: {
            Text(
                "Tells your devices when a Bot replies, messages you or needs you, even with Usual Bot closed; lets you watch a Bot’s browser; and tells Bots in your Usual Bot chats that they’re talking through Usual Bot. It does nothing for your other apps’ chats. Each device turns notifications on under Settings › Notifications."
            )
        }
    }

    @ViewBuilder private var status: some View {
        switch push.phase {
        case .loading: ProgressView().controlSize(.small)
        case .ready where push.needsUpdate:
            Text("Update available").foregroundStyle(Theme.needsYouInk)
        case .ready: Text("Installed")
        case .notInstalled: Text("Not installed").foregroundStyle(Theme.needsYouInk)
        case .failed(let message): Text(message).foregroundStyle(Theme.danger)
        }
    }

    private func install() {
        isInstalling = true
        problem = nil
        Task {
            do {
                needsRestart = try await model.installPlugin()
            } catch {
                problem = AppModel.describe(error)
            }
            isInstalling = false
        }
    }
}

/// Each Bot, once the gateway has the plugin: ready to watch, or what's left to do for it.
private struct BrowserSetup: View {
    let model: AppModel
    let bots: [Contact]
    let ask: (Contact, String) -> Void

    var body: some View {
        let browsers = bots.map { model.browser(for: $0) }
        let plugin = Self.hasPlugin(browsers.map(\.hasPlugin))
        Section {
            // The rows stay the same while the plugin check runs: swapping a lone spinner row for
            // the Bot rows makes the Mac's grouped Form drop the last row out of the section.
            if plugin == false {
                Text("Needs the Usual Bot plugin, above.").foregroundStyle(Theme.secondaryInk)
            } else {
                ForEach(bots) { bot in
                    row(bot, pluginKnown: plugin == true)
                }
            }
        } header: {
            Text("Bot’s Browser")
        } footer: {
            Text(
                "Lets you watch a Bot browse with a copy of your own browser profile, signed in where you are, in a browser with no window on the gateway. A Bot shows Ready once it browses with your real profile and its browser runs headless. Set Up turns that on for a Bot: it gets your signed-in browser, so only do it for Bots you trust with it."
            )
        }
    }

    private func row(_ bot: Contact, pluginKnown: Bool) -> some View {
        let browser = model.browser(for: bot)
        return LabeledContent(bot.name) {
            if !pluginKnown {
                ProgressView().controlSize(.small)
            } else if browser.isAvailable {
                Text("Ready")
            } else {
                HStack(spacing: 8) {
                    Text("Off").foregroundStyle(.secondary)
                    SetupMenu(
                        command: SetupCommands.turnOnBrowser(profile: browser.profile),
                        message: SetupCommands.askTurnOnBrowser(profile: browser.profile, name: bot.name),
                        bots: bots, ask: ask)
                }
            }
        }
    }

    /// One Bot's answer settles it; until one answers, it isn't known.
    private static func hasPlugin(_ answers: [Bool?]) -> Bool? {
        if answers.contains(true) { return true }
        return answers.contains(false) ? false : nil
    }
}

/// Each Bot's computer, as `display.status` reports it. Hermes sets it up; this says what's there.
private struct ComputerSetup: View {
    let model: AppModel
    let bots: [Contact]

    var body: some View {
        Section {
            ForEach(bots) { bot in
                let screen = model.screen(for: bot)
                LabeledContent(bot.name) {
                    if let status = screen.status {
                        Text(Self.describe(status))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Bot’s Computer")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "A Linux desktop Hermes runs for a Bot, which you can watch and take over. Hermes gives a Bot one when the gateway runs on Linux with the desktop packages installed, or when the Bot’s terminal runs in a Docker or SSH sandbox whose image has them. Set it up in Hermes."
                )
                Link("How a Bot’s computer works", destination: URL(string: Self.guide)!)
            }
        }
    }

    private static let guide =
        "https://github.com/usual-labs/usual-bot/blob/main/docs/guides/user-guide.md#a-bots-computer"

    private static func describe(_ status: DisplayStatus) -> String {
        if !status.supported { return String(localized: "Not on this gateway") }
        if !status.installed { return String(localized: "Desktop not installed") }
        return status.running ? String(localized: "On") : String(localized: "Ready")
    }
}
