import HermesKit
import SwiftUI

/// Next and Previous Chat: the sidebar's order, without the chats in folded sections.
enum ChatOrder {
    static func shown(_ blocks: [SidebarBlock], isFolded: (SidebarBlock.ID) -> Bool) -> [Contact] {
        blocks.flatMap { isFolded($0.id) ? [] : $0.contacts }
    }

    /// The chat `step` away from `current`, wrapping around. With none open (or one not listed),
    /// forward starts at the first and back at the last.
    static func step(from current: Contact.ID?, by step: Int, in ids: [Contact.ID]) -> Contact.ID? {
        guard !ids.isEmpty else { return nil }
        guard let index = current.flatMap({ ids.firstIndex(of: $0) }) else {
            return step > 0 ? ids.first : ids.last
        }
        return ids[((index + step) % ids.count + ids.count) % ids.count]
    }

    /// ⌘1 to ⌘9 open the first nine chats of that order.
    static func numbered(_ ids: [Contact.ID]) -> [Contact.ID: Int] {
        Dictionary(zip(ids.prefix(9), 1...9), uniquingKeysWith: { first, _ in first })
    }
}

#if os(macOS)
    /// What the main window in front offers the menu bar. `nil` actions are disabled there.
    struct WindowCommands {
        var newBot: (() -> Void)?
        var newRoom: (() -> Void)?
        var search: () -> Void
        /// Collapse or Expand Sidebar; `nil` when the window is too narrow to leave the rail.
        var sidebar: (title: LocalizedStringKey, toggle: () -> Void)?
        var previousChat: (() -> Void)?
        var nextChat: (() -> Void)?
        /// The chats ⌘1 to ⌘9 open, in order.
        var numberedChats: [(name: String, open: () -> Void)] = []
    }

    /// The open chat's side panel: an agent's profile or a room's details.
    struct ChatPanelCommand {
        let title: LocalizedStringKey
        let toggle: () -> Void
    }

    extension FocusedValues {
        @Entry var windowCommands: WindowCommands?
        @Entry var chatPanel: ChatPanelCommand?
    }

    /// The menu bar's File, View, Go and Help items for the main window.
    public struct UsualBotCommands: Commands {
        @FocusedValue(\.windowCommands) private var window
        @FocusedValue(\.chatPanel) private var panel

        public init() {}

        /// The system's Quit did nothing while a window showed a sheet: SwiftUI puts a closed sheet
        /// back while its state says it's open, and refuses to quit while one is up. So this
        /// closes the sheets and quits, and if that's refused, exits: the app keeps nothing that
        /// only quitting writes.
        static func quit() {
            for window in NSApp.windows {
                for sheet in window.sheets { sheet.close() }
            }
            NSApp.terminate(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
        }

        public var body: some Commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Usual Bot", action: Self.quit).keyboardShortcut("q")
            }
            // Replaces New Window: a second window would share the first one's open chat.
            CommandGroup(replacing: .newItem) {
                Button("New Bot…") { window?.newBot?() }
                    .keyboardShortcut("n")
                    .disabled(window?.newBot == nil)
                Button("New Room…") { window?.newRoom?() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(window?.newRoom == nil)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") { window?.search() }
                    .keyboardShortcut("f")
                    .disabled(window == nil)
            }
            CommandGroup(replacing: .sidebar) {
                Button(window?.sidebar?.title ?? "Collapse Sidebar") { window?.sidebar?.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .disabled(window?.sidebar == nil)
                Button(panel?.title ?? "Show Profile") { panel?.toggle() }
                    .keyboardShortcut("i")
                    .disabled(panel == nil)
                Divider()
            }
            CommandMenu("Go") {
                Button("Search…") { window?.search() }
                    .keyboardShortcut("k")
                    .disabled(window == nil)
                Divider()
                Button("Previous Chat") { window?.previousChat?() }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                    .disabled(window?.previousChat == nil)
                Button("Next Chat") { window?.nextChat?() }
                    .keyboardShortcut(.tab, modifiers: .control)
                    .disabled(window?.nextChat == nil)
                if let chats = window?.numberedChats, !chats.isEmpty {
                    Divider()
                    ForEach(Array(chats.enumerated()), id: \.offset) { index, chat in
                        Button(chat.name, action: chat.open)
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    }
                }
            }
            CommandGroup(replacing: .help) {
                Link("Usual Bot Help", destination: Self.guide)
            }
        }

        static let guide = URL(string: "https://github.com/usual-labs/usual-bot/blob/main/docs/guides/user-guide.md")!
    }
#endif
