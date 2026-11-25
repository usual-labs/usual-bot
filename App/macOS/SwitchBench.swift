#if DEBUG && os(macOS)
    import AppKit
    import HermesKit
    import QuartzCore

    /// `USUALBOT_SWITCH_BENCH=<file>`: opens each chat and room in turn, four times round, and writes
    /// how long each switch held the window: from choosing the chat to the next frame drawn. The
    /// first round opens chats for the first time; compare the later ones. Then the app quits.
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
        private let ids: [Contact.ID]
        private let path: String
        private var link: CADisplayLink?
        private var chosenAt: CFTimeInterval?
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
            guard step < ids.count * Self.rounds else {
                try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                exit(0)
            }
            let id = ids[step % ids.count]
            step += 1
            chosenAt = CACurrentMediaTime()
            // What the sidebar's selection is stored in (`RootView`); setting it is a click on the row.
            UserDefaults.standard.set(id, forKey: AppModel.selectedContactKey)
            lines.append("\(id)")
        }

        @objc private func frame(_ link: CADisplayLink) {
            guard let chosenAt else { return }
            lines[lines.count - 1] += String(format: " %.0f ms", (CACurrentMediaTime() - chosenAt) * 1000)
            self.chosenAt = nil
            // Long enough for anything the switch started to settle before the next one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.next() }
        }
    }
#endif
