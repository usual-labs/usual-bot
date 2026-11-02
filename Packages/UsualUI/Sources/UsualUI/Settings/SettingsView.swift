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
    /// The app's own connection settings, such as iPhone's built-in Tailscale.
    private let connectionControls: AnyView?
    @State private var page: Page? = .general
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel, desktopControls: AnyView? = nil, connectionControls: AnyView? = nil) {
        self.model = model
        self.desktopControls = desktopControls
        self.connectionControls = connectionControls
    }

    public var body: some View {
        #if os(macOS)
            HStack(spacing: 0) {
                List(Page.allCases, selection: $page) { page in
                    Label(page.title, systemImage: page.icon).tag(page)
                        .padding(.vertical, 5)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .padding(.top, 44)
                .frame(width: 190)
                .background(Theme.window)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text((page ?? .general).title)
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                    content(page ?? .general)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.pane)
            }
            // The panes run up behind the window buttons, with no title across them.
            .ignoresSafeArea(.container, edges: .top)
            .frame(width: 760, height: 600)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .appPreferences()
        #else
            // Grok's phone settings: a close button at the top left, the account (here, the
            // gateway) on top, then plain rows.
            NavigationStack {
                List {
                    Section {
                        NavigationLink(value: Page.connection) { gatewayCard }
                    }
                    Section {
                        ForEach([Page.general, .notifications, .voice]) { page in
                            NavigationLink(value: page) { Text(page.title).foregroundStyle(Theme.ink) }
                        }
                    }
                    about
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Page.self) { page in
                    content(page).navigationTitle(page.title)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Text("Close"))
                    }
                }
            }
            .appPreferences()
        #endif
    }

    #if os(iOS)
        /// Which gateway, and whether it's reachable; opens Connection.
        private var gatewayCard: some View {
            HStack(spacing: 14) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.selection, in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(model.link.dotColor)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Theme.window, lineWidth: 2))
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gatewayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(connectionStatus)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }

        private var gatewayName: String {
            if case .signedIn(let gateway) = model.session { return gateway.displayName }
            return String(localized: "Not connected")
        }
    #endif

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
                NotificationSettings(
                    push: model.push, gatewayIsUnencrypted: model.gatewayIsUnencrypted,
                    isSignedIn: model.isSignedIn)
            case .voice:
                VoiceSettings()
            case .connection:
                connection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
            if let connectionControls { connectionControls }
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
            .foregroundStyle(Theme.ink)
            Link("Source Code", destination: URL(string: "https://github.com/usual-labs/usual-bot")!)
                .foregroundStyle(Theme.ink)
            Link("Licenses and Credits", destination: URL(string: "https://github.com/usual-labs/usual-bot#license")!)
                .foregroundStyle(Theme.ink)
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
