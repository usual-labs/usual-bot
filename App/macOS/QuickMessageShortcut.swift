#if os(macOS)
    import Foundation
    import Observation

    @MainActor
    @Observable
    final class QuickMessageShortcut {
        private(set) var label: String?
        private(set) var isEnabled: Bool
        private(set) var isRecording = false
        var problem: String?
        @ObservationIgnored var action: () -> Void = {}
        @ObservationIgnored private var hotKey: HotKey?
        @ObservationIgnored private var chosen: HotKey.Combo?
        private let defaults: UserDefaults
        private let defaultCombos: [HotKey.Combo]
        private static let choiceKey = "quickMessageShortcut"
        private static let enabledKey = "quickMessageShortcutEnabled"

        init(defaults: UserDefaults = .standard, defaultCombos: [HotKey.Combo] = [.optionSpace, .controlOptionSpace]) {
            self.defaults = defaults
            self.defaultCombos = defaultCombos
            isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
            chosen = defaults.data(forKey: Self.choiceKey).flatMap {
                try? JSONDecoder().decode(HotKey.Combo.self, from: $0)
            }
            resume()
        }

        func beginRecording() {
            problem = nil
            isRecording = true
            suspend()
        }

        func endRecording() {
            guard isRecording else { return }
            isRecording = false
            resume()
        }

        func set(_ combo: HotKey.Combo) {
            isRecording = false
            suspend()
            register([combo])
            guard label != nil else {
                resume()
                problem = String(localized: "That shortcut is unavailable. Try adding Control or Command.")
                return
            }
            chosen = combo
            isEnabled = true
            problem = nil
            defaults.set(try? JSONEncoder().encode(combo), forKey: Self.choiceKey)
            defaults.set(true, forKey: Self.enabledKey)
        }

        func disable() {
            isRecording = false
            suspend()
            label = nil
            isEnabled = false
            problem = nil
            defaults.set(false, forKey: Self.enabledKey)
        }

        func restoreDefault() {
            isRecording = false
            suspend()
            register(defaultCombos)
            guard label != nil else {
                resume()
                problem = String(localized: "The default shortcuts are unavailable. Record another combination.")
                return
            }
            chosen = nil
            isEnabled = true
            problem = nil
            defaults.removeObject(forKey: Self.choiceKey)
            defaults.set(true, forKey: Self.enabledKey)
        }

        private func suspend() {
            hotKey?.unregister()
            hotKey = nil
        }

        private func resume() {
            problem = nil
            suspend()
            guard isEnabled else { label = nil; return }
            register(chosen.map { [$0] } ?? defaultCombos)
            if label == nil {
                problem = String(localized: "The shortcut is unavailable. Record a different combination.")
            }
        }

        private func register(_ combos: [HotKey.Combo]) {
            hotKey = HotKey(combos) { [weak self] in self?.action() }
            label = hotKey?.combo?.label
        }
    }
#endif
