import HermesKit
import SwiftUI
import UsualUI

@main
struct UsualBotApp: App {
    @State private var model = AppModel()
    #if os(macOS)
        @State private var presenter = BrowserSignInPresenter()
    #else
        @State private var presenter = WebAuthSignInPresenter()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView(model: model, presenter: presenter)
                .task { await model.restore() }
        }
        #if os(macOS)
            .windowToolbarStyle(.unifiedCompact)
            .defaultSize(width: 1100, height: 720)
        #endif
    }
}
