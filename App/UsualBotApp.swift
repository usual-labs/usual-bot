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
        /// The app's own Tailscale device, which gateway traffic takes while it's on.
        @State private var tailscale: BuiltInTailscale
        @State private var systemSignIn = WebAuthSignInPresenter()
        @State private var tailnetSignIn: TailnetSignInPresenter
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
            // USUALBOT_DEMO=1 shows made-up agents instead of signing in, for screenshots and for
            // trying the app without a Hermes gateway.
            let model = ProcessInfo.processInfo.environment["USUALBOT_DEMO"] == "1" ? AppModel.demo() : live()
        #else
            let model = live()
        #endif
        _model = State(initialValue: model)
        TaskNotifications.watch(model)
        #if os(macOS)
            _quickPanel = State(initialValue: QuickPanelController(model: model))
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            #if os(macOS)
                RootView(model: model, presenter: presenter)
                    .task { await model.restore() }
                    .providesMainWindow(to: quickPanel)
            #else
                RootView(model: model, presenter: signInPresenter) {
                    TailscaleConnectOption(tailscale: tailscale)
                } gatewayMenu: {
                    TailscaleMenu(tailscale: tailscale, reconnect: model.reconnect)
                }
                .task { await model.restore() }
                .onChange(of: scenePhase) { _, phase in setForeground(phase != .background) }
            #endif
        }
        #if os(macOS)
            // No title bar: the panes reach the top of the window, which drags by its background.
            .windowStyle(.hiddenTitleBar)
            .windowBackgroundDragBehavior(.enabled)
            .defaultSize(width: 1100, height: 720)
        #endif

        #if os(macOS)
            // Keeps the quick panel and the app within reach after the window is closed.
            MenuBarExtra("Usual Bot", systemImage: "bubble.left.and.bubble.right") {
                QuickPanelMenu(controller: quickPanel)
            }
        #endif
    }

    #if os(iOS)
        /// The system sheet can't reach a tailnet, so sign-in goes through the built-in device
        /// while it's on.
        private var signInPresenter: any SignInPresenter {
            tailscale.isOn ? tailnetSignIn : systemSignIn
        }

        /// iOS suspends a backgrounded app's sockets, so the app closes its gateway socket and stops
        /// the built-in Tailscale device, and reconnects on return, which starts the device again.
        private func setForeground(_ foreground: Bool) {
            model.setForeground(foreground)
            if !foreground { tailscale.suspend() }
        }
    #endif
}
