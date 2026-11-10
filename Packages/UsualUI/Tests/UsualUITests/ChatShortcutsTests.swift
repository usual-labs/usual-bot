#if os(macOS)
    import AppKit
    import Testing

    @testable import UsualUI

    struct ChatShortcutsTests {
        private func shows(_ flags: NSEvent.ModifierFlags) -> Bool {
            CommandHold.Coordinator.isCommandAlone(flags)
        }

        @Test func commandByItselfShowsTheNumbers() {
            #expect(shows(.command))
            #expect(shows([.command, .capsLock]))
            #expect(shows([.command, .numericPad]))
        }

        @Test func otherShortcutsAndNoCommandDoNot() {
            #expect(!shows([]))
            #expect(!shows(.shift))
            #expect(!shows([.command, .shift]))
            #expect(!shows([.command, .option]))
            #expect(!shows([.command, .control]))
        }
    }
#endif
