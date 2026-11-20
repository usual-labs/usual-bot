#if os(macOS)
    import SwiftUI

    /// Help ▸ Keyboard Shortcuts (⌘/): the Mac's shortcuts on one page. Keep it in step with the
    /// menu bar (`UsualBotCommands`) and the user guide's table.
    struct KeyboardShortcutsSheet: View {
        @Environment(\.dismiss) private var dismiss
        @AppStorage(AppPreferences.commandReturnKey) private var commandReturn = false

        var body: some View {
            SheetForm(title: Text("Keyboard Shortcuts"), action: SheetAction(title: "Done") { dismiss() }) {
                Form {
                    Section("Essentials") {
                        row("Search", keys: ["⌘K"])
                        row("New Bot", keys: ["⌘N"])
                        row("New Room", keys: ["⇧⌘N"])
                        row(
                            "Send", hint: commandReturn ? "↵ for a new line" : "⇧↵ for a new line",
                            keys: [commandReturn ? "⌘↵" : "↵"])
                        row("Quick message, from any app", hint: "Change it in Settings", keys: ["⌥Space"])
                        row("Settings", keys: ["⌘,"])
                        row("Keyboard shortcuts", keys: ["⌘/"])
                    }
                    Section("Chat") {
                        row("Dictate", hint: "Hold to talk", keys: ["⌘D"])
                        row("Add selection to chat", keys: ["⌘L"])
                        row("Send when the reply ends", keys: ["⌥↵"])
                        row("Stop the reply", keys: ["⌘."])
                        row("Profile or room details", keys: ["⌘I"])
                        row("Show or hide the terminal", keys: ["⌘J"])
                    }
                    Section("Navigation") {
                        row("Back / forward", keys: ["⌘[", "⌘]"])
                        row("Previous / next chat", keys: ["⌃⇧Tab", "⌃Tab"])
                        row("Go to chat", keys: ["⌘1–9"])
                        row("Collapse sidebar", keys: ["⌃⌘S"])
                    }
                    Section("Window") {
                        row("Zoom in / out", keys: ["⌘+", "⌘−"])
                        row("Actual size", keys: ["⌘0"])
                        row("Full screen", keys: ["⌃⌘F"])
                    }
                }
            }
            .zoomedFrame(width: 480, height: 640)
        }

        private func row(_ title: LocalizedStringKey, hint: LocalizedStringKey? = nil, keys: [String]) -> some View {
            LabeledContent {
                HStack(spacing: 4) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                        if index > 0 { Text(verbatim: "/").foregroundStyle(Theme.secondaryInk) }
                        KeyCap(key: key)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                    if let hint { Text(hint).foregroundStyle(Theme.secondaryInk) }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
