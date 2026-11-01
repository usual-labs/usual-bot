#if os(macOS)
    import AppKit
    import Carbon.HIToolbox
    import ServiceManagement
    import SwiftUI

    struct DesktopSettings: View {
        let controller: QuickPanelController
        @State private var loginStatus = SMAppService.mainApp.status
        @State private var loginProblem: String?
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                        set: setLaunchAtLogin))
                if loginStatus == .requiresApproval {
                    Button("Approve in Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginProblem { Text(loginProblem).foregroundStyle(.red) }
            } header: {
                Text("Mac")
            } footer: {
                Text("Usual Bot stays in the menu bar after you close its window.")
            }
            Section {
                LabeledContent("Keyboard shortcut") {
                    ShortcutRecorder(shortcut: controller.keyboardShortcut)
                        .frame(width: 180, height: 28)
                }
                HStack {
                    Button("Restore Default") { controller.keyboardShortcut.restoreDefault() }
                    Button("Disable Shortcut") { controller.keyboardShortcut.disable() }
                        .disabled(!controller.keyboardShortcut.isEnabled)
                }
                if let problem = controller.keyboardShortcut.problem {
                    Text(problem).foregroundStyle(.red)
                } else if !controller.keyboardShortcut.isEnabled {
                    Text("Shortcut disabled. You can still open Quick Message from the menu bar.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Quick Message")
            } footer: {
                Text(
                    "Click the shortcut and press a new combination with Control, Option or Command. Escape cancels. The default is ⌥Space, or ⌃⌥Space if macOS requires it."
                )
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { loginStatus = SMAppService.mainApp.status }
            }
            .onAppear { loginStatus = SMAppService.mainApp.status }
        }

        private func setLaunchAtLogin(_ enabled: Bool) {
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginProblem = nil
            } catch {
                loginProblem = error.localizedDescription
            }
            loginStatus = SMAppService.mainApp.status
        }
    }

    /// A first-responder button captures only while recording, without Accessibility permission.
    private struct ShortcutRecorder: NSViewRepresentable {
        let shortcut: QuickMessageShortcut

        func makeNSView(context: Context) -> RecorderButton {
            let button = RecorderButton()
            button.recordingChanged = { recording in
                if recording { shortcut.beginRecording() } else { shortcut.endRecording() }
            }
            button.captured = { shortcut.set($0) }
            button.invalid = { shortcut.problem = $0 }
            return button
        }

        func updateNSView(_ button: RecorderButton, context: Context) {
            button.shortcutLabel = shortcut.label
            if !shortcut.isRecording { button.finishRecording() }
            button.updateTitle()
        }

        static func dismantleNSView(_ button: RecorderButton, coordinator: ()) {
            button.finishRecording()
        }
    }

    private final class RecorderButton: NSButton {
        var shortcutLabel: String?
        var recordingChanged: ((Bool) -> Void)?
        var captured: ((HotKey.Combo) -> Void)?
        var invalid: ((String) -> Void)?
        private var recording = false

        init() {
            super.init(frame: .zero)
            bezelStyle = .rounded
            target = self
            action = #selector(startRecording)
            setAccessibilityLabel(String(localized: "Quick Message keyboard shortcut"))
            setAccessibilityHelp(String(localized: "Activate, then press a shortcut. Escape cancels."))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var acceptsFirstResponder: Bool { true }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
            if let newWindow {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowResignedKey),
                    name: NSWindow.didResignKeyNotification, object: newWindow)
            }
            super.viewWillMove(toWindow: newWindow)
        }

        @objc private func windowResignedKey() { finishRecording() }

        func updateTitle() {
            title =
                recording
                ? String(localized: "Press shortcut…") : shortcutLabel ?? String(localized: "Record Shortcut…")
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.baseWritingDirection = .leftToRight
            attributedTitle = NSAttributedString(string: title, attributes: [.paragraphStyle: paragraph])
        }

        @objc private func startRecording() {
            if recording { finishRecording(); return }
            window?.makeFirstResponder(self)
            recording = true
            recordingChanged?(true)
            updateTitle()
        }

        func finishRecording() {
            guard recording else { return }
            recording = false
            recordingChanged?(false)
            updateTitle()
        }

        override func resignFirstResponder() -> Bool {
            finishRecording()
            return super.resignFirstResponder()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            record(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            record(event)
        }

        private func record(_ event: NSEvent) {
            if event.keyCode == 53 { finishRecording(); return }
            guard !event.isARepeat else { return }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            guard !flags.intersection([.control, .option, .command]).isEmpty else {
                invalid?(String(localized: "Include Control, Option or Command in the shortcut."))
                NSSound.beep()
                return
            }
            let special: [UInt16: String] = [
                36: "Return", 48: "Tab", 49: "Space", 51: "⌫", 117: "⌦",
                123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End",
                116: "Page Up", 121: "Page Down",
                122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
                100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14",
                113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
            ]
            guard let key = special[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased(),
                !key.isEmpty, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else {
                invalid?(String(localized: "Choose a letter, number, arrow or Space with a modifier key."))
                return
            }
            var modifiers: UInt32 = 0
            var label = ""
            for (flag, carbon, symbol): (NSEvent.ModifierFlags, UInt32, String) in [
                (.control, UInt32(controlKey), "⌃"), (.option, UInt32(optionKey), "⌥"),
                (.shift, UInt32(shiftKey), "⇧"), (.command, UInt32(cmdKey), "⌘"),
            ] where flags.contains(flag) {
                modifiers |= carbon
                label += symbol
            }
            // End recording before installing, so finishing cannot restore over the new choice.
            finishRecording()
            captured?(HotKey.Combo(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label + key))
        }
    }
#endif
