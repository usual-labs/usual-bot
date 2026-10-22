import SwiftUI
import UsualUI

@main
struct UsualBotApp: App {
    var body: some Scene {
        WindowGroup {
            // Sample contacts until the app can sign in to a gateway (milestone 1).
            RootView(contacts: SampleData.contacts())
        }
        #if os(macOS)
            .windowToolbarStyle(.unifiedCompact)
            .defaultSize(width: 1100, height: 720)
        #endif
    }
}
