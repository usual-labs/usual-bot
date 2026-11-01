import HermesKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Preferences for this device; agent and gateway administration stay in Hermes.
public struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general, notifications, voice, connection
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .notifications: "Notifications"
            case .voice: "Voice"
            case .connection: "Connection"
            }
        }
        var icon: String {
            switch self {
            case .general: "gearshape"
            case .notifications: "bell"
            case .voice: "waveform"
            case .connection: "network"
            }
        }
    }

    private let model: AppModel
    private let desktopControls: AnyView?
    @State private var page: Page? = .general
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel, desktopControls: AnyView? = nil) {
        self.model = model
        self.desktopControls = desktopControls
    }

    public var body: some View {
        #if os(macOS)
            HStack(spacing: 0) {
                List(Page.allCases, selection: $page) { page in
                    Label(page.title, systemImage: page.icon).tag(page)
                        .padding(.vertical, 5)
                }
                .listStyle(.sidebar)
                .frame(width: 190)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text((page ?? .general).title)
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                    content(page ?? .general)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 760, height: 600)
            .background(Theme.window)
            .appPreferences()
        #else
            NavigationStack {
                List {
                    ForEach(Page.allCases) { page in
                        NavigationLink(value: page) { Label(page.title, systemImage: page.icon) }
                    }
                    about
                }
                .navigationTitle("Settings")
                .navigationDestination(for: Page.self) { page in
                    content(page).navigationTitle(page.title)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
            .appPreferences()
        #endif
    }

    private func content(_ page: Page) -> some View {
        Form {
            switch page {
            case .general:
                GeneralSettings()
                if let desktopControls { desktopControls }
                #if os(macOS)
                    about
                #endif
            case .notifications:
                NotificationSettings()
            case .voice:
                VoiceSettings()
            case .connection:
                connection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var connection: some View {
        if case .signedIn(let gateway) = model.session {
            Section("Gateway") {
                LabeledContent("Address") {
                    Text(gateway.baseURL.absoluteString).textSelection(.enabled)
                }
                LabeledContent("Status", value: connectionStatus)
                if let version = model.gatewayDetails?.version {
                    LabeledContent("Hermes version", value: version)
                }
                if let account = model.gatewayDetails?.account {
                    LabeledContent("Signed in as", value: account)
                }
                #if os(macOS)
                    if let url = URL(string: "hermes://open/settings"),
                        NSWorkspace.shared.urlForApplication(toOpen: url) != nil
                    {
                        Link("Open Hermes for advanced settings", destination: url)
                    }
                #endif
            }
            .task { await model.loadGatewayDetails() }
            Section {
                Button("Sign Out", role: .destructive) { model.signOut() }
            } footer: {
                Text("Signing out removes this gateway’s saved sign-in and cached chats from this device.")
            }
        } else {
            Section { Text("You’re not connected to a gateway. Sign in from the main window.") }
        }
    }

    private var connectionStatus: String {
        switch model.link {
        case .connecting: String(localized: "Connecting…")
        case .offline(let reason): String(localized: "Offline, retrying…") + " " + reason
        case .online:
            model.gatewayDetails?.isHealthy == false
                ? String(localized: "Connected, some parts need attention") : String(localized: "Connected")
        }
    }

    private var about: some View {
        Section("About Usual Bot") {
            LabeledContent("Version", value: version)
            Link(
                "User Guide",
                destination: URL(string: "https://github.com/usual-labs/usual-bot/blob/main/docs/guides/user-guide.md")!
            )
            Link("Source Code", destination: URL(string: "https://github.com/usual-labs/usual-bot")!)
            Link("Licenses and Credits", destination: URL(string: "https://github.com/usual-labs/usual-bot#license")!)
            Text("An independent app, not made by, affiliated with or endorsed by Nous Research.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct GeneralSettings: View {
    @AppStorage(AppPreferences.appearanceKey) private var appearance = "system"
    @AppStorage(AppPreferences.textSizeKey) private var textSize = 0
    #if os(macOS)
        @AppStorage(AppPreferences.commandReturnKey) private var commandReturn = false
    #endif

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearance) {
                Text("Follow System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("Chat text size", selection: $textSize) {
                Text("Small").tag(-2)
                Text("Default").tag(0)
                Text("Large").tag(3)
                Text("Extra Large").tag(6)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                MarkdownView(
                    "Here’s a reply with **bold text**, a [link](https://github.com/usual-labs/usual-bot), and `code`.")
            }
            .padding(.vertical, 8)
        }
        #if os(macOS)
            Section {
                Picker("Send messages with", selection: $commandReturn) {
                    Text("Return").tag(false)
                    Text("⌘Return").tag(true)
                }
            } header: {
                Text("Chat")
            } footer: {
                Text(
                    "Shift-Return always adds a new line. Quick Message uses Return to send and ⌘Return to open the full chat."
                )
            }
        #endif
    }
}
