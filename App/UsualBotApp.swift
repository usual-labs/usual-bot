import HermesKit
import SwiftUI
import UsualUI

@main
struct UsualBotApp: App {
    @State private var model: AppModel
    #if os(macOS)
        @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #else
        @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif
    #if os(macOS)
        @State private var presenter = BrowserSignInPresenter()
        @State private var quickPanel: QuickPanelController
    #else
        /// The app's own Tailscale device, which gateway traffic takes while it's on.
        @State private var tailscale: BuiltInTailscale
        @State private var systemSignIn = WebAuthSignInPresenter()
        @State private var tailnetSignIn: TailnetSignInPresenter
        @State private var backgroundLink: BackgroundLink
        @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
        #if os(iOS)
            let tailscale = BuiltInTailscale()
            _tailscale = State(initialValue: tailscale)
            _tailnetSignIn = State(initialValue: TailnetSignInPresenter(tailnet: tailscale.tailnet))
            let live = { AppModel(session: { try await tailscale.session() }) }
        #else
            let live = { AppModel() }
        #endif
        #if DEBUG
            // USUALBOT_DEMO=1 (or --demo) shows made-up agents instead of signing in, for screenshots and for
            // trying the app without a Hermes gateway.
            let demo =
                ProcessInfo.processInfo.environment["USUALBOT_DEMO"] == "1"
                || ProcessInfo.processInfo.arguments.contains("--demo")
                || ProcessInfo.processInfo.arguments.contains("--demo-long-chat")
            let model =
                demo
                ? AppModel.demo(longConversations: ProcessInfo.processInfo.arguments.contains("--demo-long-chat"))
                : live()
        #else
            let model = live()
        #endif
        _model = State(initialValue: model)
        #if os(macOS)
            let quickPanel = QuickPanelController(model: model)
            _quickPanel = State(initialValue: quickPanel)
            AgentNotifications.shared.watch(model, showApp: { quickPanel.showMainWindow() })
            // The window has no title bar for tabs to sit under; this also removes the tab menu items.
            NSWindow.allowsAutomaticWindowTabbing = false
        #else
            AgentNotifications.shared.watch(model, showApp: {})
            _backgroundLink = State(initialValue: BackgroundLink(model: model, suspend: { tailscale.suspend() }))
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            rootView
                .task { await model.restore() }
                .task { PushRegistration.start(model.relay) }
                .task { await model.update.watch() }
                .onOpenURL { model.open($0) }
                // Asked once you're in, not from the background, where iOS can't show the question.
                .onChange(of: model.session, initial: true) { _, session in
                    if case .signedIn = session { Task { await AgentNotifications.shared.askForPermission() } }
                }
                #if os(macOS)
                    .providesMainWindow(to: quickPanel)
                    // A link opens its chat in this window, not a new one.
                    .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                #else
                    // iOS suspends a backgrounded app's sockets; reconnect on return instead.
                    .onChange(of: scenePhase) { _, phase in backgroundLink.sceneChanged(to: phase) }
                #endif
        }
        #if os(iOS)
            .backgroundTask(.appRefresh(BackgroundLink.checkInID)) { await backgroundLink.checkIn() }
        #endif
        #if os(macOS)
            // No title bar: the panes reach the top of the window, which drags by its background.
            .windowStyle(.hiddenTitleBar)
            .handlesExternalEvents(matching: ["*"])
            .windowBackgroundDragBehavior(.enabled)
            .defaultSize(width: 1100, height: 720)
            .commands { UsualBotCommands() }
        #endif

        #if os(macOS)
            // An agent's computer, live, from the chat's Computer button.
            WindowGroup("Computer", id: "bot-screen", for: String.self) { $contactID in
                if let contactID { BotScreenWindow(model: model, contactID: contactID) }
            }
            .defaultSize(width: 1000, height: 680)
            // Opened only from a chat, for its agent: File › New would show an empty window.
            .commandsRemoved()

            // An agent's browser, live, from the chat's Browser button.
            WindowGroup("Browser", id: "bot-browser", for: String.self) { $contactID in
                if let contactID { BotBrowserWindow(model: model, contactID: contactID) }
            }
            // 1440 wide pages show at full size, with room for the bar above them.
            .defaultSize(width: 1440, height: 880)
            .commandsRemoved()

            Settings {
                SettingsView(model: model, desktopControls: AnyView(DesktopSettings(controller: quickPanel)))
            }

            // Keeps the quick panel and the app within reach after the window is closed.
            MenuBarExtra {
                QuickPanelMenu(controller: quickPanel)
            } label: {
                // Named, or VoiceOver reads the symbol's name, "Conversation".
                Image(systemName: "bubble.left.and.bubble.right")
                    .accessibilityLabel(Text("Usual Bot"))
            }
        #endif
    }

    #if os(macOS)
        private var rootView: some View {
            RootView(model: model, presenter: presenter)
        }
    #else
        private var rootView: some View {
            RootView(model: model, presenter: signInPresenter) {
                TailscaleConnectOption(tailscale: tailscale)
            } gatewayMenu: {
                TailscaleMenu(tailscale: tailscale, reconnect: model.reconnect)
            }
        }

        /// The system sheet can't reach a tailnet, so sign-in goes through the built-in device
        /// while it's on.
        private var signInPresenter: any SignInPresenter {
            tailscale.isOn ? tailnetSignIn : systemSignIn
        }
    #endif
}
