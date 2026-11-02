import HermesKit
import SwiftUI
import UsualUI

@main
struct UsualBotApp: App {
    @State private var model: AppModel
    #if os(macOS)
        @State private var presenter = BrowserSignInPresenter()
        @State private var quickPanel: QuickPanelController
    #else
        @State private var presenter = WebAuthSignInPresenter()
        @State private var backgroundLink: BackgroundLink
        @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
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
                : AppModel()
        #else
            let model = AppModel()
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
            _backgroundLink = State(initialValue: BackgroundLink(model: model))
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(model: model, presenter: presenter)
                .task { await model.restore() }
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
        #endif

        #if os(macOS)
            Settings {
                SettingsView(model: model, desktopControls: AnyView(DesktopSettings(controller: quickPanel)))
            }

            // Keeps the quick panel and the app within reach after the window is closed.
            MenuBarExtra("Usual Bot", systemImage: "bubble.left.and.bubble.right") {
                QuickPanelMenu(controller: quickPanel)
            }
        #endif
    }
}
