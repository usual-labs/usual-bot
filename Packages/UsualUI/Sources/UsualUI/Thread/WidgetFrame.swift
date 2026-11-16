import HermesKit
import SwiftUI
import WebKit

/// What a widget's page tells the app. The one way anything gets from a page to the app: each
/// case comes from its own script message channel (`WidgetFrame.Coordinator`).
enum WidgetMessage: Equatable {
    /// The page's size, from `WidgetPage.measureScript`. `width` is 0 when it couldn't be measured.
    case size(height: CGFloat, width: CGFloat)
    /// The page called `window.hermes.send` (`WidgetPage.sendScript`), with whatever it passed.
    case send(WidgetSendRequest)
}

/// A page's `send()` waiting for its answer, which resolves the page's promise.
@MainActor final class WidgetSendRequest: Equatable {
    /// What the page passed, unchecked.
    let body: Any
    /// When you last tapped or pressed a key in the page, as the app's own script saw it.
    let tappedAt: ContinuousClock.Instant?
    private var answer: ((WidgetAck) -> Void)?

    init(body: Any, tappedAt: ContinuousClock.Instant?, answer: @escaping (WidgetAck) -> Void) {
        self.body = body
        self.tappedAt = tappedAt
        self.answer = answer
    }

    /// Answers the page, once.
    func reply(_ ack: WidgetAck) {
        answer?(ack)
        answer = nil
    }

    nonisolated static func == (lhs: WidgetSendRequest, rhs: WidgetSendRequest) -> Bool { lhs === rhs }
}

/// An inline widget's page, running in WebKit with nothing of the app's: its own storage that
/// ends with it, no way to leave the page, and no message channel the page can reach. The theme
/// and the size report run in a script world of their own, so the page can't see or fake them.
///
/// Talking back to the chat (`window.hermes.send`) is the one channel in the page's own world,
/// sent on as `WidgetMessage.send`; `InlineWidget` checks and answers it.
@MainActor struct WidgetFrame {
    /// The page's HTML, as the agent wrote it.
    let html: String
    let theme: WidgetPage.Theme
    /// Whether the page scrolls inside the frame (iPhone): only when it doesn't fit, so a swipe
    /// over a widget that fits scrolls the chat.
    let scrolls: Bool
    /// Whether the page can talk back here, which `window.hermes.canSend` tells it.
    var canSend = false
    let onMessage: (WidgetMessage) -> Void

    @Environment(\.openURL) private var openURL

    /// The app's script world: the page's own scripts run in another.
    private static let world = WKContentWorld.world(name: "UsualBotWidget")

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor func make(_ coordinator: Coordinator) -> WKWebView {
        coordinator.parent = self
        let configuration = WKWebViewConfiguration()
        // A store of its own that's never written to disk: a page can't read another's cookies or
        // storage, or keep anything once it's closed.
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        #if os(iOS)
            configuration.allowsInlineMediaPlayback = true
            configuration.dataDetectorTypes = []
        #endif
        let scripts = configuration.userContentController
        scripts.addUserScript(
            WKUserScript(
                source: WidgetPage.themeScript(theme), injectionTime: .atDocumentStart, forMainFrameOnly: true,
                in: Self.world))
        scripts.addUserScript(
            WKUserScript(
                source: WidgetPage.measureScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true,
                in: Self.world))
        scripts.add(WeakHandler(coordinator), contentWorld: Self.world, name: WidgetPage.sizeChannel)
        // Before the page's own scripts, so none can stop the event first.
        scripts.addUserScript(
            WKUserScript(
                source: WidgetPage.gestureScript, injectionTime: .atDocumentStart, forMainFrameOnly: true,
                in: Self.world))
        scripts.add(WeakHandler(coordinator), contentWorld: Self.world, name: WidgetPage.gestureChannel)
        scripts.addUserScript(
            WKUserScript(
                source: WidgetPage.sendScript(canSend: canSend), injectionTime: .atDocumentStart,
                forMainFrameOnly: true, in: .page))
        scripts.addScriptMessageHandler(
            WeakReplyHandler(coordinator), contentWorld: .page, name: WidgetPage.sendChannel)

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        view.allowsLinkPreview = false
        #if os(macOS)
            // Transparent, so the page sits on the message as Hermes's does.
            view.setValue(false, forKey: "drawsBackground")
        #else
            view.isOpaque = false
            view.backgroundColor = .clear
            view.scrollView.backgroundColor = .clear
            view.scrollView.bounces = false
            view.scrollView.contentInsetAdjustmentBehavior = .never
            view.scrollView.isScrollEnabled = scrolls
        #endif
        coordinator.theme = theme
        coordinator.load(html, in: view)
        return view
    }

    @MainActor private func update(_ view: WKWebView, _ coordinator: Coordinator) {
        coordinator.parent = self
        #if os(iOS)
            view.scrollView.isScrollEnabled = scrolls
        #endif
        if coordinator.theme != theme {
            coordinator.theme = theme
            view.evaluateJavaScript(WidgetPage.retheme(theme), in: nil, in: Self.world) { _ in }
        }
        // The agent rewrote the page: it starts again with the new one.
        if coordinator.html != html { coordinator.load(html, in: view) }
    }

    @MainActor private static func dismantle(_ view: WKWebView) {
        view.stopLoading()
        view.configuration.userContentController.removeAllScriptMessageHandlers()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
        WKScriptMessageHandlerWithReply
    {
        var parent: WidgetFrame?
        var theme: WidgetPage.Theme?
        /// The page showing.
        private(set) var html: String?
        /// When you last tapped or pressed a key in the page.
        private(set) var tappedAt: ContinuousClock.Instant?
        /// The page loaded; any later navigation of the frame would leave it.
        private var loaded = false

        func load(_ html: String, in view: WKWebView) {
            self.html = html
            loaded = false
            // A tap on the old page doesn't let the new one send.
            tappedAt = nil
            // No base URL: the page has no origin to share and its relative links lead nowhere.
            view.loadHTMLString(html, baseURL: nil)
        }

        func userContentController(
            _ controller: WKUserContentController, didReceive message: WKScriptMessage,
            replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
        ) {
            // A frame inside the page (an ad, an embed) isn't the widget.
            guard message.name == WidgetPage.sendChannel, message.frameInfo.isMainFrame, let parent else {
                replyHandler(WidgetAck(failure: .undelivered).object, nil)
                return
            }
            parent.onMessage(
                .send(WidgetSendRequest(body: message.body, tappedAt: tappedAt) { replyHandler($0.object, nil) }))
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            // A tap in a frame inside the page (an ad, an embed) isn't a tap on the widget.
            if message.name == WidgetPage.gestureChannel {
                if message.frameInfo.isMainFrame { tappedAt = .now }
                return
            }
            guard message.name == WidgetPage.sizeChannel, let size = WidgetPage.size(from: message.body) else {
                return
            }
            parent?.onMessage(.size(height: size.height, width: size.width))
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            // Frames inside the page (a video, a map) load as they would in Hermes.
            if let target = action.targetFrame, !target.isMainFrame {
                let scheme = action.request.url?.scheme?.lowercased() ?? ""
                decisionHandler(["http", "https", "about", "data", "blob"].contains(scheme) ? .allow : .cancel)
                return
            }
            if !loaded, action.request.url?.absoluteString == "about:blank" {
                loaded = true
                decisionHandler(.allow)
                return
            }
            // The page stays; a link you tap opens in your browser, as a link in a message does.
            if action.navigationType == .linkActivated { openOutside(action.request.url) }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
            decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
        ) {
            // Nothing downloads to the device from a widget.
            decisionHandler(response.canShowMIMEType ? .allow : .cancel)
        }

        /// `target="_blank"` links and `window.open`: no new windows, but a tapped link opens.
        func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
            for action: WKNavigationAction, windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if action.navigationType == .linkActivated { openOutside(action.request.url) }
            return nil
        }

        /// No camera or microphone for a widget.
        func webView(
            _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
            decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.deny)
        }

        private func openOutside(_ url: URL?) {
            guard let url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
            parent?.openURL(url)
        }
    }

    /// The same for the page's `send()` channel, which answers.
    private final class WeakReplyHandler: NSObject, WKScriptMessageHandlerWithReply {
        weak var target: (any WKScriptMessageHandlerWithReply)?

        init(_ target: any WKScriptMessageHandlerWithReply) { self.target = target }

        func userContentController(
            _ controller: WKUserContentController, didReceive message: WKScriptMessage,
            replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
        ) {
            guard let target else { return replyHandler(WidgetAck(failure: .undelivered).object, nil) }
            target.userContentController(controller, didReceive: message, replyHandler: replyHandler)
        }
    }

    /// The content controller keeps its handlers; this keeps it from keeping the coordinator.
    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: (any WKScriptMessageHandler)?

        init(_ target: any WKScriptMessageHandler) { self.target = target }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }
}

#if os(macOS)
    extension WidgetFrame: NSViewRepresentable {
        func makeNSView(context: Context) -> WKWebView { make(context.coordinator) }
        func updateNSView(_ view: WKWebView, context: Context) { update(view, context.coordinator) }
        static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { dismantle(view) }
    }
#else
    extension WidgetFrame: UIViewRepresentable {
        func makeUIView(context: Context) -> WKWebView { make(context.coordinator) }
        func updateUIView(_ view: WKWebView, context: Context) { update(view, context.coordinator) }
        static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { dismantle(view) }
    }
#endif
