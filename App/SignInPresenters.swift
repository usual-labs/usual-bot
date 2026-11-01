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
    import Tailnet
    import UIKit
    import WebKit

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

    /// Shows sign-in in an in-app web view whose traffic goes through the app's own Tailscale
    /// device, for a tailnet gateway while the Tailscale VPN is off. The system sheet can't: it
    /// loads pages outside the app, where the tailnet isn't reachable. The gateway's redirect to
    /// `http://127.0.0.1` still reaches the app's listener; the proxy dials loopback directly.
    @MainActor
    final class TailnetSignInPresenter: NSObject, SignInPresenter, UIAdaptivePresentationControllerDelegate {
        private let tailnet: Tailnet
        private var sheet: UIViewController?
        private var onCancel: (@MainActor () -> Void)?

        init(tailnet: Tailnet) {
            self.tailnet = tailnet
        }

        func present(_ url: URL, onCancel: @escaping @MainActor () -> Void) {
            self.onCancel = onCancel
            Task {
                guard let proxies = try? await tailnet.session().configuration.proxyConfigurations else {
                    return cancel()
                }
                let store = WKWebsiteDataStore.nonPersistent()
                store.proxyConfigurations = proxies
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = store
                let webView = WKWebView(frame: .zero, configuration: configuration)
                let page = UIViewController()
                page.view = webView
                page.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.cancel() })
                let sheet = UINavigationController(rootViewController: page)
                sheet.presentationController?.delegate = self
                Self.topViewController()?.present(sheet, animated: true)
                self.sheet = sheet
                webView.load(URLRequest(url: url))
            }
        }

        func dismiss() {
            sheet?.dismiss(animated: true)
            sheet = nil
            onCancel = nil
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            sheet = nil
            cancel()
        }

        private func cancel() {
            let onCancel = onCancel
            dismiss()
            onCancel?()
        }

        private static func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            var top = scenes.compactMap(\.keyWindow).first?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }
#endif
