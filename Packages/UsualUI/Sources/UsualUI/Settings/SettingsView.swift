import HermesKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Preferences for this device; agent and gateway administration stay in Hermes.
public struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general, notifications, voice, connection, usage
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .notifications: "Notifications"
            case .voice: "Voice"
            case .connection: "Connection"
            case .usage: "Usage"
            }
        }
        var icon: String {
            switch self {
            case .general: "gearshape"
            case .notifications: "bell"
            case .voice: "waveform"
            case .connection: "network"
            case .usage: "chart.bar"
            }
        }
    }

    private let model: AppModel
    private let desktopControls: AnyView?
    /// The app's own connection settings, such as iPhone's built-in Tailscale.
    private let connectionControls: AnyView?
    #if os(macOS)
        @State private var page = Page.general
    #endif
    @State private var confirmsSignOut = false
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel, desktopControls: AnyView? = nil, connectionControls: AnyView? = nil) {
        self.model = model
        self.desktopControls = desktopControls
        self.connectionControls = connectionControls
    }

    public var body: some View {
        #if os(macOS)
            // The system's Settings window: a tab for each page, each a grouped form.
            TabView(selection: $page) {
                ForEach(Page.allCases) { page in
                    Tab(value: page) {
                        content(page)
                    } label: {
                        Label(page.title, systemImage: page.icon)
                    }
                }
            }
            .frame(width: 640, height: 560)
            // The app's ink, as in the main window, not the system's blue; switches take the
            // system's own colour (`SystemSwitchStyle`).
            .tint(Theme.ink)
            .toggleStyle(.systemSwitch)
            .appPreferences()
        #else
            // Grok's phone settings: a close button at the top left, the account (here, the
            // gateway) on top, then plain rows.
            NavigationStack {
                List {
                    Section {
                        gatewayRows
                        // Grok keeps usage with the account; here the gateway is the account.
                        NavigationLink(value: Page.usage) {
                            // The gateway card's columns, so the symbol sits under its circle and
                            // the title under its name.
                            HStack(spacing: Self.symbolSpacing) {
                                Image(systemName: Page.usage.icon)
                                    .font(.system(size: 18))
                                    .frame(width: Self.symbolWidth)
                                    .accessibilityHidden(true)
                                Text("Usage")
                            }
                            .foregroundStyle(Theme.ink)
                        }
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
                        Button(role: .close) { dismiss() }
                    }
                }
            }
            .tint(Theme.ink)
            .toggleStyle(.systemSwitch)
            .appPreferences()
        #endif
    }

    #if os(iOS)
        private static let symbolWidth: CGFloat = 44
        private static let symbolSpacing: CGFloat = 14

        /// Each gateway: the one in use opens Connection, another switches to it. Then Add Gateway.
        @ViewBuilder private var gatewayRows: some View {
            if model.gateways.isEmpty || !model.isSignedIn {
                NavigationLink(value: Page.connection) {
                    gatewayCard(
                        name: String(localized: "Not connected"), status: connectionStatus, dot: model.link.dotColor)
                }
            } else {
                ForEach(model.gateways) { gateway in
                    if gateway.id == model.activeGateway?.id {
                        NavigationLink(value: Page.connection) {
                            gatewayCard(
                                name: gateway.displayName, status: connectionStatus, dot: model.link.dotColor,
                                isChecked: model.gateways.count > 1)
                        }
                    } else {
                        Button {
                            model.switchTo(gateway.id)
                        } label: {
                            gatewayCard(
                                name: gateway.displayName,
                                status: model.gatewaysWithNews.contains(gateway.id)
                                    ? String(localized: "New notifications") : String(localized: "Tap to switch"),
                                dot: Theme.secondaryInk, hasNews: model.gatewaysWithNews.contains(gateway.id))
                        }
                        .accessibilityHint(Text("Switches to this gateway"))
                    }
                }
                Button {
                    dismiss()
                    model.addGateway()
                } label: {
                    HStack(spacing: Self.symbolSpacing) {
                        Image(systemName: "plus")
                            .font(.system(size: 18))
                            .frame(width: Self.symbolWidth)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Gateway")
                            if !model.canAddGateway {
                                Text("Usual Bot connects to two gateways at most.")
                                    .scaledFont(size: 14)
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                        }
                    }
                    .foregroundStyle(model.canAddGateway ? Theme.ink : Theme.secondaryInk)
                }
                .disabled(!model.canAddGateway)
            }
        }

        /// A gateway, and whether it's reachable.
        private func gatewayCard(
            name: String, status: String, dot: Color, isChecked: Bool = false, hasNews: Bool = false
        ) -> some View {
            HStack(spacing: Self.symbolSpacing) {
                Image(systemName: "server.rack")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink)
                    .frame(width: Self.symbolWidth, height: Self.symbolWidth)
                    .background(Theme.selection, in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(dot)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Theme.window, lineWidth: 2))
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .scaledFont(size: 17, weight: .medium)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1, accessibility: 3)
                    Text(status)
                        .scaledFont(size: 14)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if hasNews { NewsDot() }
                if isChecked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel(Text("In use"))
                }
            }
            .padding(.vertical, 4)
        }
    #endif

    @ViewBuilder private func content(_ page: Page) -> some View {
        if page == .usage {
            // Its own form: a Bot's numbers open inside it.
            UsageSettings(model: model)
        } else {
            form(page)
        }
    }

    private func form(_ page: Page) -> some View {
        Form {
            switch page {
            case .general:
                GeneralSettings()
                if model.isSignedIn { HiddenBotsSection(model: model) }
                BrowserSettings()
                if let desktopControls { desktopControls }
                #if os(macOS)
                    about
                #endif
            case .notifications:
                NotificationSettings(
                    push: model.push,
                    bots: model.contacts.filter { $0.kind == .agent }.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    },
                    isSignedIn: model.isSignedIn, isOffHere: model.activeGateway?.notifies == false,
                    needsUpdate: model.pushPluginNeedsUpdate)
            case .voice:
                VoiceSettings()
            case .connection:
                connection
            case .usage:
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .thinScroller()
    }

    @ViewBuilder private var connection: some View {
        if case .signedIn(let gateway) = model.session {
            #if os(macOS)
                // On iPhone these are at the top of Settings.
                Section {
                    ForEach(model.gateways) { saved in
                        LabeledContent {
                            if saved.id == model.activeGateway?.id {
                                Text("In use")
                            } else {
                                Button("Switch") { model.switchTo(saved.id) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(saved.displayName)
                                if model.gatewaysWithNews.contains(saved.id) {
                                    NewsDot()
                                    Text("New notifications").foregroundStyle(Theme.secondaryInk)
                                }
                            }
                        }
                    }
                    Button("Add Gateway…") { model.addGateway() }
                        .disabled(!model.canAddGateway)
                } header: {
                    Text("Gateways")
                } footer: {
                    if !model.canAddGateway { Text("Usual Bot connects to two gateways at most.") }
                }
            #endif
            Section {
                if let saved = model.activeGateway {
                    LabeledContent("Name") {
                        TextField("Name", text: name(of: saved), prompt: Text(saved.address.displayName))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .textInputTint()
                    }
                    Toggle("Notifications", isOn: notifies(saved))
                    if model.pushPluginNeedsUpdate {
                        Text("Update Usual Push on this gateway so its notifications open the right chat.")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
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
            } header: {
                Text("Gateway")
            } footer: {
                if model.gateways.count > 1 { Text("Its name and notifications are for this device only.") }
            }
            .task(id: model.activeGateway?.id) { await model.loadGatewayDetails() }
            if let connectionControls { connectionControls }
            Section {
                Button("Sign Out…", role: .destructive) { confirmsSignOut = true }
                    .signOutConfirmation(
                        isPresented: $confirmsSignOut, name: model.activeGateway?.displayName ?? gateway.displayName,
                        signOut: model.signOut)
            } footer: {
                SignOutNote()
            }
        } else {
            Section { Text("You’re not connected to a gateway. Sign in from the main window.") }
        }
    }

    private func name(of gateway: SavedGateway) -> Binding<String> {
        Binding(get: { model.activeGateway?.name ?? "" }, set: { model.rename(gateway.id, to: $0) })
    }

    private func notifies(_ gateway: SavedGateway) -> Binding<Bool> {
        Binding(
            get: { model.activeGateway?.notifies ?? true },
            set: { on in Task { await model.setNotifications(on) } })
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
            if let newest = model.update.newest {
                Link(
                    newest.version.isEmpty || newest.isSameVersion
                        ? String(localized: "Update in TestFlight")
                        : String(localized: "Update to \(newest.version) in TestFlight"),
                    destination: newest.testFlight
                )
                .foregroundStyle(Theme.ink)
            }
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
    @AppStorage(AppPreferences.streamRepliesKey) private var streamsReplies = true
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
            .clickable()
            Picker("Chat text size", selection: $textSize) {
                Text("Small").tag(-2)
                Text("Default").tag(0)
                Text("Large").tag(3)
                Text("Extra Large").tag(6)
            }
            .clickable()
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview").font(.caption).foregroundStyle(.secondary)
                MarkdownView(
                    "Here’s a reply with **bold text**, a [link](https://github.com/usual-labs/usual-bot), and `code`.")
            }
            .padding(.vertical, 8)
        }
        Section {
            Toggle("Show replies as they’re written", isOn: $streamsReplies)
                .toggleStyle(.systemSwitch)
            #if os(macOS)
                Picker("Send messages with", selection: $commandReturn) {
                    Text("Return").tag(false)
                    Text("⌘Return").tag(true)
                }
                .clickable()
            #endif
        } header: {
            Text("Chat")
        } footer: {
            #if os(macOS)
                Text(
                    "With replies not shown as they’re written, each message appears once it’s finished. Shift-Return always adds a new line. Quick Message uses Return to send and ⌘Return to open the full chat."
                )
            #else
                Text("With this off, each message appears once it’s finished.")
            #endif
        }
    }
}
