import AuthenticationServices
import SwiftUI

/// Opens an app's sign-in page: the default browser on the Mac, the system sign-in sheet on
/// iPhone. Neither page comes back to Usual Bot (it ends on the vendor's done page or the gateway's
/// own callback) and Hermes reports the result, so the sheet stays until you close it or `close()`
/// is called, which the card does once the app is connected.
@MainActor
struct SignInPage: DynamicProperty {
    #if os(iOS)
        @Environment(\.webAuthenticationSession) private var session
        @State private var sheet: Task<Void, Never>?
    #else
        @Environment(\.openURL) private var openURL
    #endif

    func open(_ url: URL) {
        #if os(iOS)
            sheet?.cancel()
            sheet = Task {
                // Never answers with a callback: the scheme is unused, and closing the sheet throws.
                _ = try? await session.authenticate(
                    using: url, callbackURLScheme: "usualbot-unused", preferredBrowserSession: .shared)
            }
        #else
            openURL(url)
        #endif
    }

    /// Closes the sheet on iPhone. The Mac's browser tab is the browser's.
    func close() {
        #if os(iOS)
            sheet?.cancel()
            sheet = nil
        #endif
    }
}
