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

        /// The widest scroll view in any window: the conversation, not the sidebar. The demo opens
        /// a Bot's Computer window too, which can be wider than the main one.
        private static func transcript() -> NSScrollView? {
            var found: [NSScrollView] = []
            func walk(_ view: NSView) {
                if let scroll = view as? NSScrollView { found.append(scroll) }
                view.subviews.forEach(walk)
            }
            for window in NSApp.windows where window.isVisible { window.contentView.map(walk) }
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
        /// Points sent since the last frame, and a piece of text followed on screen: moving further
        /// than that in a frame is a jump, such as earlier messages added above without the reader
        /// kept in place. Event timing alone accounts for a frame's worth of steps either way.
        private var sentSinceFrame: CGFloat = 0
        private weak var anchor: NSView?
        private var anchorY: CGFloat?
        private var jumps = 0
        private var worstJump: CGFloat = 0

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
            followAnchor()
        }

        private func followAnchor() {
            let sent = sentSinceFrame
            sentSinceFrame = 0
            let frame = anchor.flatMap { $0.window == nil ? nil : $0.convert($0.bounds, to: scrollView) }
            if phase != "idle", let frame, let anchorY {
                // Scrolling by `sent` moves what's shown by as much the other way, flipped or not.
                let jump = abs(frame.minY - anchorY) - abs(sent)
                if jump > 50 { jumps += 1 }
                worstJump = max(worstJump, jump)
            }
            if frame.map({ !scrollView.bounds.insetBy(dx: 0, dy: 40).intersects($0) }) ?? true {
                anchor = pickAnchor()
            }
            anchorY = anchor.map { $0.convert($0.bounds, to: scrollView).minY }
        }

        /// A text view in the middle of what's shown.
        private func pickAnchor() -> NSView? {
            var found: [NSView] = []
            func walk(_ view: NSView) {
                if view is NSTextView { found.append(view) }
                view.subviews.forEach(walk)
            }
            if let doc = scrollView.documentView { walk(doc) }
            let middle = scrollView.bounds.insetBy(dx: 0, dy: scrollView.bounds.height / 4)
            return found.first { middle.intersects($0.convert($0.bounds, to: scrollView)) }
        }

        /// Gestures of 0.8 s each, `step` points every 1/120 s, with a short rest between.
        private func run(_ name: String, gestures: Int, step: Int32) async {
            stamps = []
            jumps = 0
            worstJump = 0
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
                        "%@: frames %.0f, missed %.0f (%.0f%%), worst gap %.0f ms, gaps over 3 frames %d, jumps over 50 pt %d (worst %.0f pt), moved %.0f pt, content %.0f→%.0f pt",
                    name, expected, missed, expected > 0 ? missed / expected * 100 : 0, worst, long, jumps, worstJump,
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
            sentSinceFrame += CGFloat(dy)
            scrollView.scrollWheel(with: event)
        }
    }
#endif
