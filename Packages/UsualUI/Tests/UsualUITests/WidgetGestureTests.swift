#if os(macOS)
    import AppKit
    import Testing
    import WebKit

    @testable import UsualUI

    /// A widget's page in real WebKit: a send carries a tap only when you really tapped. Clicks
    /// are made as AppKit events, which WebKit marks trusted; a page's own `el.click()` and timers
    /// aren't.
    @MainActor @Suite(.serialized)
    struct WidgetGestureTests {
        private static let html = """
            <a id="again" role="button" data-hermes-send="Check again"
              style="display:block;position:absolute;left:0;top:0;width:200px;height:100px">Check again</a>
            """

        private final class Box {
            var requests: [WidgetSendRequest] = []
        }

        private func open() async throws -> (WKWebView, NSWindow, Box) {
            let box = Box()
            let frame = WidgetFrame(
                html: Self.html,
                theme: WidgetPage.Theme(
                    dark: false, foreground: "black", mutedForeground: "gray", accent: "blue", border: "gray",
                    card: "white", fontSize: 15),
                scrolls: false, canSend: true
            ) { message in
                if case .send(let request) = message {
                    box.requests.append(request)
                    request.reply(.sent)
                }
            }
            let coordinator = frame.makeCoordinator()
            let view = frame.make(coordinator)
            let window = NSWindow(
                contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200), styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            view.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
            window.contentView = view
            window.orderFrontRegardless()
            // The view starts on an empty page of its own, without the scripts.
            try await waitFor {
                let state = try? await view.evaluateJavaScript("document.readyState + typeof window.hermes")
                return state as? String == "completeobject"
            }
            // Keeps the coordinator, which the view holds only weakly.
            objc_setAssociatedObject(view, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN)
            return (view, window, box)
        }

        private func waitFor(_ condition: () async -> Bool) async throws {
            for _ in 0..<200 {
                if await condition() { return }
                // sleep-ok: WebKit runs in another process; this waits for its answer.
                try await Task.sleep(for: .milliseconds(25))
            }
            Issue.record("Timed out")
        }

        private func click(_ view: WKWebView, _ window: NSWindow) {
            // Inside the link, at the page's top left: the web view is flipped.
            let point = view.convert(CGPoint(x: CGFloat(50), y: CGFloat(50)), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
            }
        }

        @Test func aRealClickOnADataHermesSendElementCarriesItsTap() async throws {
            let (view, window, box) = try await open()
            defer { window.close() }
            click(view, window)
            try await waitFor { box.requests.count == 1 }
            let request = try #require(box.requests.first)
            #expect(request.body as? String == "Check again")
            let tappedAt = try #require(request.tappedAt)
            #expect(ContinuousClock.now - tappedAt < .seconds(3))
        }

        @Test func aScriptedClickOrATimerCarriesNoTap() async throws {
            let (view, window, box) = try await open()
            defer { window.close() }
            _ = try? await view.evaluateJavaScript(
                """
                document.getElementById("again").click();
                document.getElementById("again").dispatchEvent(new PointerEvent("pointerdown", {bubbles: true}));
                setTimeout(function() { window.hermes.send("Clear old logs") }, 10);
                """)
            try await waitFor { box.requests.count == 2 }
            #expect(box.requests.map { $0.body as? String } == ["Check again", "Clear old logs"])
            #expect(box.requests.allSatisfy { $0.tappedAt == nil })
        }
    }
#endif
