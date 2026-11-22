import HermesKit
import SwiftUI
import UsualUI

/// Usual Bot in the system share sheet (iPhone) and Share menu (Mac): it saves what you shared
/// and opens the app, which asks which chat it goes to. All of it is `ShareView`; this only hosts
/// it, hands over what was shared and opens the app.
#if os(iOS)
    import UIKit

    final class ShareViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            let host = UIHostingController(
                rootView: shareView(for: extensionContext) { [weak self] in await self?.openApp() ?? false })
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }

        /// iOS gives a share extension no supported way to open its app (`NSExtensionContext.open`
        /// answers no here), but the app's `UIApplication` is in this controller's responder chain.
        /// Its `open(_:options:completionHandler:)` is marked unavailable to extensions, so it's
        /// called through the runtime. Other apps' share extensions, such as T3 Code's, do the same.
        private func openApp() async -> Bool {
            guard let url = appURL else { return false }
            var responder: UIResponder? = self
            while let current = responder, !(current is UIApplication) { responder = current.next }
            let selector = NSSelectorFromString("openURL:options:completionHandler:")
            guard let application = responder, let method = class_getInstanceMethod(type(of: application), selector)
            else { return false }
            typealias Open =
                @convention(c) (
                    AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
                ) -> Void
            let open = unsafeBitCast(method_getImplementation(method), to: Open.self)
            return await withCheckedContinuation { continuation in
                open(application, selector, url as NSURL, NSDictionary()) { continuation.resume(returning: $0) }
            }
        }
    }
#else
    import AppKit

    final class ShareViewController: NSViewController {
        override func loadView() {
            let host = NSHostingView(rootView: shareView(for: extensionContext) { await Self.openApp() })
            host.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
            view = host
            preferredContentSize = host.frame.size
        }

        private static func openApp() async -> Bool {
            guard let url = appURL else { return false }
            return await withCheckedContinuation { continuation in
                NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    continuation.resume(returning: error == nil)
                }
            }
        }
    }
#endif

/// The app's `share` link, under the scheme only this build's app answers to.
private var appURL: URL? {
    let scheme = Bundle.main.object(forInfoDictionaryKey: "UsualAppScheme") as? String
    return URL(string: "\(scheme ?? "usualbot")://share")
}

@MainActor
private func shareView(for context: NSExtensionContext?, openApp: @escaping () async -> Bool) -> ShareView {
    let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    return ShareView(
        providers: items.flatMap { $0.attachments ?? [] }, container: ShareContainer.appGroup(), openApp: openApp,
        done: { context?.completeRequest(returningItems: nil) },
        cancel: { context?.cancelRequest(withError: CocoaError(.userCancelled)) })
}
