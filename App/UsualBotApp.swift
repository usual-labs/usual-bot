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
        @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        #if os(macOS)
            _quickPanel = State(initialValue: QuickPanelController(model: model))
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(model: model, presenter: presenter)
                .task { await model.restore() }
                #if os(macOS)
                    .providesMainWindow(to: quickPanel)
                #else
                    // iOS suspends a backgrounded app's sockets; reconnect on return instead.
                    .onChange(of: scenePhase) { _, phase in model.setForeground(phase != .background) }
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
}
