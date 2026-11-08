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
            PushSetup(push: model.push, bots: bots, ask: ask)
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

/// The `usual-push` plugin (`Integrations/hermes-push`), which notifies your devices.
private struct PushSetup: View {
    let push: PushSettings
    let bots: [Contact]
    let ask: (Contact, String) -> Void

    var body: some View {
        Section {
            LabeledContent("usual-push plugin") {
                switch push.phase {
                case .loading: ProgressView().controlSize(.small)
                case .ready: Text("Installed")
                case .notInstalled: Text("Not installed").foregroundStyle(Theme.needsYouInk)
                case .failed(let message): Text(message).foregroundStyle(Theme.danger)
                }
            }
            if push.phase == .notInstalled {
                SetupStep(
                    "On the computer your gateway runs on, install it, then restart the gateway:",
                    command: SetupCommands.install(.push), message: SetupCommands.askInstall(.push), bots: bots,
                    ask: ask)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(
                "Tells your devices when a Bot replies, messages you or needs you, even with Usual Bot closed. Each device then turns itself on under Settings › Notifications."
            )
        }
    }
}

/// The `usual-browser` plugin, then each Bot: ready to watch, or what's left to do for it.
private struct BrowserSetup: View {
    let model: AppModel
    let bots: [Contact]
    let ask: (Contact, String) -> Void

    var body: some View {
        let browsers = bots.map { model.browser(for: $0) }
        let plugin = Self.hasPlugin(browsers.map(\.hasPlugin))
        Section {
            LabeledContent("usual-browser plugin") {
                switch plugin {
                case true: Text("Installed")
                case false: Text("Not installed").foregroundStyle(Theme.needsYouInk)
                default: ProgressView().controlSize(.small)
                }
            }
            if plugin == false {
                SetupStep(
                    "On the computer your gateway runs on, install it, then restart the gateway:",
                    command: SetupCommands.install(.browser), message: SetupCommands.askInstall(.browser),
                    bots: bots, ask: ask)
            }
            if plugin == true {
                ForEach(bots) { bot in
                    let browser = model.browser(for: bot)
                    LabeledContent(bot.name) {
                        if browser.isAvailable {
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
            }
        } header: {
            Text("Bot’s Browser")
        } footer: {
            Text(
                "Lets you watch a Bot browse with a copy of your own browser profile, signed in where you are, in a browser with no window on the gateway. A Bot shows Ready once it browses with your real profile and its browser runs headless. Set Up turns that on for a Bot: it gets your signed-in browser, so only do it for Bots you trust with it."
            )
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
