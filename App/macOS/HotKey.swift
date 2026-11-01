#if os(macOS)
    import Carbon.HIToolbox

    /// A system-wide keyboard shortcut. Carbon hot keys are the one way to get one in a sandboxed
    /// app without asking for Accessibility access.
    @MainActor
    final class HotKey {
        struct Combo: Codable, Equatable {
            let keyCode: UInt32
            let modifiers: UInt32
            /// How menus show it, e.g. "⌥Space".
            let label: String

            static let optionSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥Space")
            static let controlOptionSpace = Combo(
                keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥Space")
        }

        /// The shortcut the system accepted; `nil` when it took none.
        private(set) var combo: Combo?
        private var ref: EventHotKeyRef?
        private var id: UInt32?

        private static var actions: [UInt32: () -> Void] = [:]
        private static var nextID: UInt32 = 1
        private static var handlerInstalled = false
        /// "UsBt": tags this app's hot keys.
        private static let signature: OSType = 0x5573_4274

        /// Registers the first available combination. The default falls back to ⌃⌥Space when
        /// macOS or another app reserves ⌥Space.
        init(_ combos: [Combo], action: @escaping () -> Void) {
            Self.installHandler()
            let id = Self.nextID
            Self.nextID += 1
            for combo in combos {
                var ref: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                    // The default allows other apps to share a shortcut and compete for presses.
                    GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
                if status == noErr, let ref {
                    self.ref = ref
                    self.id = id
                    self.combo = combo
                    Self.actions[id] = action
                    break
                }
            }
        }

        /// Release the old registration before changing or recording a shortcut.
        func unregister() {
            if let ref { UnregisterEventHotKey(ref) }
            if let id { Self.actions.removeValue(forKey: id) }
            ref = nil
            id = nil
            combo = nil
        }

        private static func installHandler() {
            guard !handlerInstalled else { return }
            handlerInstalled = true
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, _ in
                    var hotKey = EventHotKeyID()
                    GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
                    let id = hotKey.id
                    // Carbon delivers application events on the main thread.
                    MainActor.assumeIsolated { HotKey.actions[id]?() }
                    return noErr
                }, 1, &pressed, nil, nil)
        }
    }
#endif
