#if DEBUG && os(macOS)
    import AppKit
    import HermesKit
    import QuartzCore

    /// `USUALBOT_SWITCH_BENCH=<file>`: opens each chat and room in turn, four times round, and writes
    /// how long each switch held the window: from choosing the chat to the next frame drawn, then
    /// how long the main thread overran its frames in the second after (work the switch left behind,
    /// such as earlier pages added above what's on screen). The first round opens chats for the
    /// first time; compare the later ones. Then it goes back and forth between three of them, as
    /// you do between the chats you're in, with lines marked `recent`. Then the app quits.
    @MainActor final class SwitchBench: NSObject {
        private static var running: SwitchBench?

        static func startIfAsked(model: AppModel) {
            guard let path = ProcessInfo.processInfo.environment["USUALBOT_SWITCH_BENCH"], !path.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                running = SwitchBench(ids: model.contacts.map(\.id), path: path)
                running?.start()
            }
        }

        private static let rounds = 4
        /// The back-and-forth pass: this many switches round the first three chats.
        private static let recentSwitches = 30
        /// Longer than anything a switch puts off, such as earlier messages added after the chat is drawn.
        private static let settle: CFTimeInterval = 1
        private let ids: [Contact.ID]
        private let path: String
        private var link: CADisplayLink?
        private var chosenAt: CFTimeInterval?
        /// The last frame after the first, while the switch settles.
        private var settlingSince: CFTimeInterval?
        private var lastFrame: CFTimeInterval = 0
        private var overrun: CFTimeInterval = 0
        private var lines: [String] = []
        private var step = 0

        private init(ids: [Contact.ID], path: String) {
            self.ids = ids
            self.path = path
        }

        private func start() {
            guard let view = NSApp.windows.first(where: \.isVisible)?.contentView, !ids.isEmpty else {
                try? "no window or no chats\n".write(toFile: path, atomically: true, encoding: .utf8)
                return
            }
            link = view.displayLink(target: self, selector: #selector(frame(_:)))
            link?.add(to: .main, forMode: .common)
            next()
        }

        private func next() {
            let cycle = ids.count * Self.rounds
            guard step < cycle + Self.recentSwitches else {
                try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                exit(0)
            }
            let recent = step >= cycle
            let id = recent ? ids[(step - cycle) % min(3, ids.count)] : ids[step % ids.count]
            step += 1
            chosenAt = CACurrentMediaTime()
            // What the sidebar's selection is stored in (`RootView`); setting it is a click on the row.
            UserDefaults.standard.set(id, forKey: AppModel.selectedContactKey)
            lines.append(recent ? "recent \(id)" : "\(id)")
        }

        @objc private func frame(_ link: CADisplayLink) {
            let now = CACurrentMediaTime()
            defer { lastFrame = now }
            if let since = settlingSince {
                overrun += max(0, now - lastFrame - link.duration * 1.5)
                guard now - since >= Self.settle else { return }
                lines[lines.count - 1] += String(format: " then %.0f ms", overrun * 1000)
                settlingSince = nil
                next()
                return
            }
            guard let chosenAt else { return }
            lines[lines.count - 1] += String(format: " %.0f ms", (now - chosenAt) * 1000)
            self.chosenAt = nil
            // Long enough for anything the switch started to settle before the next one.
            settlingSince = now
            overrun = 0
        }
    }
#endif
