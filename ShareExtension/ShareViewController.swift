import HermesKit
import SwiftUI
import UsualUI

/// Usual Bot in the system share sheet (iPhone) and Share menu (Mac): pick a Bot or room, add a
/// note, and it's sent from here or left for the app to send. All of it is `ShareView`; this only
/// hosts it and hands over what was shared.
#if os(iOS)
    import UIKit

    final class ShareViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            let host = UIHostingController(rootView: shareView(for: extensionContext))
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }
#else
    import AppKit

    final class ShareViewController: NSViewController {
        override func loadView() {
            let host = NSHostingView(rootView: shareView(for: extensionContext))
            host.frame = NSRect(x: 0, y: 0, width: 420, height: 520)
            view = host
            preferredContentSize = host.frame.size
        }
    }
#endif

@MainActor
private func shareView(for context: NSExtensionContext?) -> ShareView {
    let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    let container = ShareContainer.appGroup()
    // On iPhone it sends itself when it can. The Mac's sign-in is in the app's file-based keychain,
    // which the extension can't read without asking for your password, so there the app sends.
    #if os(iOS)
        let sender = container.map(ShareSender.live)
    #else
        let sender: ShareSender? = nil
    #endif
    return ShareView(
        providers: items.flatMap { $0.attachments ?? [] }, container: container, sender: sender,
        done: { context?.completeRequest(returningItems: nil) },
        cancel: { context?.cancelRequest(withError: CocoaError(.userCancelled)) })
}
