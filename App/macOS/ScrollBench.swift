#if DEBUG && os(macOS)
    import AppKit
    import QuartzCore

    /// `USUALBOT_SCROLL_BENCH=<file>`: scrolls the open chat up through its history and back down, as
    /// trackpad gestures sent to its scroll view, and writes how many frames the window missed to
    /// `<file>`. The events go to the app itself, so the Mac's pointer and focus stay untouched.
    @MainActor final class ScrollBench: NSObject {
        private static var running: ScrollBench?

        static func startIfAsked() {
            guard let path = ProcessInfo.processInfo.environment["USUALBOT_SCROLL_BENCH"], !path.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard let scrollView = transcript() else {
                    try? "no transcript scroll view\n".write(toFile: path, atomically: true, encoding: .utf8)
                    return
                }
                running = ScrollBench(scrollView: scrollView, path: path)
                running?.start()
            }
        }

        /// The widest scroll view in the main window: the conversation, not the sidebar.
        private static func transcript() -> NSScrollView? {
            let window = NSApp.windows.filter(\.isVisible).max { $0.frame.width < $1.frame.width }
            var found: [NSScrollView] = []
            func walk(_ view: NSView) {
                if let scroll = view as? NSScrollView { found.append(scroll) }
                view.subviews.forEach(walk)
            }
            if let content = window?.contentView { walk(content) }
            return found.max { $0.frame.width < $1.frame.width }
        }

        private let scrollView: NSScrollView
        private let path: String
        private var link: CADisplayLink?
        private var stamps: [CFTimeInterval] = []
        private var duration: CFTimeInterval = 1 / 60
        private var phase = "idle"
        private var report: [String] = []
        private var driver: Timer?

        private init(scrollView: NSScrollView, path: String) {
            self.scrollView = scrollView
            self.path = path
        }

        private func start() {
            link = scrollView.displayLink(target: self, selector: #selector(frame(_:)))
            link?.add(to: .main, forMode: .common)
            Task { @MainActor in
                await run("up", gestures: 10, step: 10)
                await run("down", gestures: 5, step: -10)
                await run("up again", gestures: 5, step: 10)
                link?.invalidate()
                try? (report.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }

        @objc private func frame(_ link: CADisplayLink) {
            duration = link.duration > 0 ? link.duration : duration
            if phase != "idle" { stamps.append(link.timestamp) }
        }

        /// Gestures of 0.8 s each, `step` points every 1/120 s, with a short rest between.
        private func run(_ name: String, gestures: Int, step: Int32) async {
            stamps = []
            phase = name
            let startOffset = scrollView.contentView.bounds.origin.y
            let startHeight = scrollView.documentView?.frame.height ?? 0
            for _ in 0..<gestures {
                send(0, phase: .began)
                for _ in 0..<96 {
                    send(step, phase: .changed)
                    try? await Task.sleep(for: .milliseconds(8))
                }
                send(0, phase: .ended)
                try? await Task.sleep(for: .milliseconds(250))
            }
            phase = "idle"
            let gaps = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
            let expected = gaps.reduce(0, +) / duration
            let missed = gaps.map { max(($0 / duration).rounded() - 1, 0) }.reduce(0, +)
            let worst = (gaps.max() ?? 0) * 1000
            let long = gaps.filter { $0 > duration * 3.5 }.count
            report.append(
                String(
                    format:
                        "%@: frames %.0f, missed %.0f (%.0f%%), worst gap %.0f ms, gaps over 3 frames %d, moved %.0f pt, content %.0f→%.0f pt",
                    name, expected, missed, expected > 0 ? missed / expected * 100 : 0, worst, long,
                    scrollView.contentView.bounds.origin.y - startOffset, startHeight,
                    scrollView.documentView?.frame.height ?? 0))
        }

        private func send(_ dy: Int32, phase: NSEvent.Phase) {
            guard
                let cg = CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)
            else { return }
            let point = scrollView.convert(NSPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), to: nil)
            if let window = scrollView.window {
                cg.location = CGPoint(
                    x: window.frame.minX + point.x,
                    y: (NSScreen.screens.first?.frame.height ?? 0) - window.frame.minY - point.y)
                cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
            }
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
            let value: Int64 =
                switch phase {
                case .began: 1
                case .ended: 4
                default: 2
                }
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: value)
            guard let event = NSEvent(cgEvent: cg) else { return }
            scrollView.scrollWheel(with: event)
        }
    }
#endif
