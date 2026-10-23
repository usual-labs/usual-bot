#if os(macOS)
    import AppKit
    import HermesKit
    import SwiftUI
    import UsualUI
    import os

    /// The quick message panel: floats over every app and Space without taking focus from the
    /// app you're in, and goes away when you click elsewhere or press Escape.
    @MainActor
    @Observable
    final class QuickPanelController {
        private let model: AppModel
        @ObservationIgnored private var panel: QuickPanel?
        @ObservationIgnored private var hosting: NSHostingController<QuickMessageView>?
        @ObservationIgnored private var hotKey: HotKey?
        /// Opens the main window when it was closed; set by the main window.
        @ObservationIgnored var openMainWindow: () -> Void = {}

        /// The panel's shortcut, as menus show it; `nil` when the system took none.
        private(set) var shortcut: String?

        /// The card is 640 pt wide; the rest leaves room for its shadow and an answer.
        private static let size = NSSize(width: 720, height: 680)

        init(model: AppModel) {
            self.model = model
            hotKey = HotKey([.optionSpace, .controlOptionSpace]) { [weak self] in self?.toggle() }
            shortcut = hotKey?.combo?.label
            Self.log.notice("Quick message shortcut: \(self.shortcut ?? "none", privacy: .public)")
            #if DEBUG
                // USUALBOT_SHOW_QUICK_PANEL=1 opens the panel shortly after launch, for screenshots.
                if ProcessInfo.processInfo.environment["USUALBOT_SHOW_QUICK_PANEL"] == "1" {
                    FileHandle.standardError.write(Data("Quick message shortcut: \(shortcut ?? "none")\n".utf8))
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(6))
                        self?.show()
                    }
                }
            #endif
        }

        private static let log = Logger(subsystem: "UsualBot", category: "quick-message")

        func toggle() {
            if panel?.isVisible == true { close() } else { show() }
        }

        func show() {
            let panel = self.panel ?? makePanel()
            hosting?.rootView = view(shownAt: .now)
            place(panel)
            // The shortcut fires while another app is active: order the panel in regardless,
            // then take the keyboard without activating Usual Bot.
            panel.orderFrontRegardless()
            panel.makeKey()
        }

        func close() {
            panel?.orderOut(nil)
        }

        /// Brings the main window forward, opening it again if it was closed.
        func showMainWindow() {
            NSApp.activate()
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openMainWindow()
            }
        }

        private func openChat(_ id: Contact.ID) {
            close()
            // The main window's sidebar keeps its selection here.
            UserDefaults.standard.set(id, forKey: "selectedContact")
            showMainWindow()
        }

        private func view(shownAt: Date) -> QuickMessageView {
            QuickMessageView(
                model: model, shownAt: shownAt, openChat: { [weak self] in self?.openChat($0) },
                close: { [weak self] in self?.close() })
        }

        private func makePanel() -> QuickPanel {
            let panel = QuickPanel(
                contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            let hosting = NSHostingController(rootView: view(shownAt: .now))
            hosting.sizingOptions = []
            hosting.view.frame = NSRect(origin: .zero, size: Self.size)
            panel.contentViewController = hosting
            panel.setContentSize(Self.size)
            panel.onResignKey = { [weak self] in self?.close() }
            self.panel = panel
            self.hosting = hosting
            return panel
        }

        /// Centred on the screen with the pointer, a little above the middle, like Spotlight.
        private func place(_ panel: NSPanel) {
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
                return
            }
            let area = screen.visibleFrame
            panel.setFrameTopLeftPoint(
                NSPoint(x: area.midX - Self.size.width / 2, y: area.maxY - area.height * 0.16))
        }
    }

    /// A borderless panel that takes the keyboard, closes on Escape and when you click elsewhere.
    final class QuickPanel: NSPanel {
        var onResignKey: () -> Void = {}

        override var canBecomeKey: Bool { true }

        override func cancelOperation(_ sender: Any?) {
            orderOut(nil)
        }

        override func resignKey() {
            super.resignKey()
            onResignKey()
        }
    }

    /// The menu bar item: the panel, the main window, and Quit, while the app runs without a window.
    struct QuickPanelMenu: View {
        let controller: QuickPanelController

        var body: some View {
            Button(
                controller.shortcut.map { String(localized: "Quick Message (\($0))") }
                    ?? String(localized: "Quick Message")
            ) {
                controller.show()
            }
            Button("Open Usual Bot") { controller.showMainWindow() }
            Divider()
            Button("Quit Usual Bot") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    extension View {
        /// Lets the quick panel reopen the main window after it was closed.
        func providesMainWindow(to controller: QuickPanelController) -> some View {
            modifier(ProvidesMainWindow(controller: controller))
        }
    }

    private struct ProvidesMainWindow: ViewModifier {
        let controller: QuickPanelController
        @Environment(\.openWindow) private var openWindow

        func body(content: Content) -> some View {
            content.onAppear {
                let openWindow = openWindow
                controller.openMainWindow = { openWindow(id: "main") }
                #if DEBUG
                    // USUALBOT_WINDOW_WIDTH=560 opens the window that wide, for screenshots of the
                    // narrow layout.
                    if let width = ProcessInfo.processInfo.environment["USUALBOT_WINDOW_WIDTH"].flatMap(Double.init) {
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            guard
                                let window = NSApp.windows.first(where: {
                                    $0.identifier?.rawValue.hasPrefix("main") == true
                                })
                            else { return }
                            var frame = window.frame
                            frame.size.width = width
                            window.setFrame(frame, display: true)
                        }
                    }
                #endif
            }
        }
    }
#endif
