import Foundation
import HermesKit

#if os(macOS)
    import AppKit

    /// Opens sign-in in the default browser, where the user is usually already signed in to
    /// their identity provider. The gateway's redirect lands on the app's loopback listener.
    @MainActor
    final class BrowserSignInPresenter: SignInPresenter {
        func present(_ url: URL, onCancel: @escaping @MainActor () -> Void) {
            NSWorkspace.shared.open(url)
        }

        func dismiss() {
            NSApp.activate()
        }
    }
#endif

#if os(iOS)
    import AuthenticationServices
    import UIKit

    /// Shows sign-in in an in-app browser sheet. The app stays in the foreground, so its loopback
    /// listener can receive the redirect. The callback scheme is never used: the gateway only
    /// redirects to `http://127.0.0.1`, and the app closes the sheet itself once that arrives.
    @MainActor
    final class WebAuthSignInPresenter: NSObject, SignInPresenter, ASWebAuthenticationPresentationContextProviding {
        private var session: ASWebAuthenticationSession?

        func present(_ url: URL, onCancel: @escaping @MainActor () -> Void) {
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme("usualbot-unused")) {
                _, error in
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    Task { @MainActor in onCancel() }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        func dismiss() {
            session?.cancel()
            session = nil
        }

        nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                if let window = scenes.compactMap(\.keyWindow).first { return window }
                return UIWindow(windowScene: scenes[0])
            }
        }
    }
#endif
