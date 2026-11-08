#if os(macOS)
    import AppKit
    import Testing

    @testable import UsualUI

    struct TypingFocusTests {
        private func types(_ characters: String, _ modifiers: NSEvent.ModifierFlags = []) -> Bool {
            TypingFocus.Coordinator.types(characters, modifiers: modifiers)
        }

        @Test func lettersAndSymbolsStartAMessage() {
            #expect(types("h"))
            #expect(types("H", .shift))
            #expect(types("/"))
            #expect(types("@", .option))
            #expect(types("é"))
        }

        @Test func shortcutsAndControlKeysStayWhereTheyAre() {
            #expect(!types("k", .command))
            #expect(!types("a", .control))
            #expect(!types(" "))
            #expect(!types("\r"))
            #expect(!types("\t"))
            #expect(!types("\u{1B}"))
            #expect(!types("\u{F700}", .function))
            #expect(!types("\u{F700}"))
            #expect(!types(""))
        }
    }
#endif
