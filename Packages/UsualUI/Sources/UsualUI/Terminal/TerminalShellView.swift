#if os(macOS)
    import AppKit
    import HermesKit
    import SwiftUI

    /// The shell's screen. Click it and type: keys go to the shell as a terminal sends them, ⌘V
    /// pastes, and ⌘ shortcuts stay the menu bar's. The shell is told the drawer's size in
    /// characters, so it wraps where the drawer does.
    struct TerminalShellView: View {
        let terminal: BotTerminal
        let focus: FocusState<Bool>.Binding
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private var size: CGFloat { TerminalStyle.fontSize * Zoom.factor(dynamicTypeSize) }

        var body: some View {
            let cell = TerminalStyle.cell(size: size)
            let screen = terminal.screen
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(screen.lines.enumerated()), id: \.element.id) { index, line in
                        let cursor =
                            focus.wrappedValue && screen.cursorVisible && index == screen.cursorLine
                            ? screen.cursorColumn : nil
                        Text(TerminalStyle.text(line, cursor: cursor, size: size))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: cell.height, alignment: .leading)
                    }
                }
                .padding(TerminalStyle.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .scrollIndicators(.automatic)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { area in
                let columns = Int((area.width - TerminalStyle.padding * 2) / cell.width)
                let rows = Int((area.height - TerminalStyle.padding * 2) / cell.height)
                terminal.resize(columns: max(columns, 20), rows: max(rows, 4))
            }
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = true }
            .focusable()
            .focused(focus)
            .focusEffectDisabled()
            .onKeyPress(phases: [.down, .repeat]) { press in
                guard let bytes = TerminalKeys.bytes(for: press) else { return .ignored }
                terminal.send(bytes)
                return .handled
            }
            .onPasteCommand(of: [.plainText]) { _ in
                if let text = NSPasteboard.general.string(forType: .string) { terminal.paste(text) }
            }
            .contextMenu {
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(terminal.screen.text, forType: .string)
                }
                Button("Paste") {
                    if let text = NSPasteboard.general.string(forType: .string) { terminal.paste(text) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Shell"))
            .accessibilityValue(Text(verbatim: String(screen.text.suffix(400))))
            .accessibilityHint(Text("Type to send keys to the shell"))
        }
    }

    /// What a terminal sends for a key: xterm's sequences in normal cursor mode.
    enum TerminalKeys {
        static func bytes(for press: KeyPress) -> String? {
            // ⌘ belongs to the menu bar: ⌘J hides the drawer, ⌘V pastes.
            if press.modifiers.contains(.command) { return nil }
            switch press.key {
            case .return: return "\r"
            case .delete: return press.modifiers.contains(.option) ? "\u{1B}\u{7F}" : "\u{7F}"
            case .deleteForward: return "\u{1B}[3~"
            case .tab: return press.modifiers.contains(.shift) ? "\u{1B}[Z" : "\t"
            case .escape: return "\u{1B}"
            case .upArrow: return "\u{1B}[A"
            case .downArrow: return "\u{1B}[B"
            case .rightArrow: return press.modifiers.contains(.option) ? "\u{1B}f" : "\u{1B}[C"
            case .leftArrow: return press.modifiers.contains(.option) ? "\u{1B}b" : "\u{1B}[D"
            case .home: return "\u{1B}[H"
            case .end: return "\u{1B}[F"
            case .pageUp: return "\u{1B}[5~"
            case .pageDown: return "\u{1B}[6~"
            default: break
            }
            if press.modifiers.contains(.control) { return control(press.key.character) }
            return press.characters.isEmpty ? nil : press.characters
        }

        /// ⌃A to ⌃Z and the few others a terminal sends as control characters.
        static func control(_ key: Character) -> String? {
            let lower = key.lowercased()
            guard let scalar = lower.unicodeScalars.first, lower.unicodeScalars.count == 1 else { return nil }
            switch scalar {
            case "a"..."z": return String(UnicodeScalar(UInt8(scalar.value - 96)))
            case "[": return "\u{1B}"
            case "\\": return "\u{1C}"
            case "]": return "\u{1D}"
            case " ", "@", "2": return "\u{0}"
            default: return nil
            }
        }
    }
#endif
