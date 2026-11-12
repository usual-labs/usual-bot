import Testing

@testable import UsualUI

struct TypedLineBreakTests {
    @Test func breakGoesWhereTheCursorIs() {
        var text = "hello world"
        let at = text.index(text.startIndex, offsetBy: 5)
        let cursor = text.insertLineBreak(replacing: at..<at)
        #expect(text == "hello\n world")
        #expect(text[cursor...] == " world")
    }

    @Test func breakReplacesTheSelection() {
        var text = "hello big world"
        let lower = text.index(text.startIndex, offsetBy: 5)
        let upper = text.index(lower, offsetBy: 4)
        let cursor = text.insertLineBreak(replacing: lower..<upper)
        #expect(text == "hello\n world")
        #expect(text[cursor...] == " world")
    }

    /// Pasted Windows text can end in "\r": the typed "\n" joins it into one character.
    @Test func breakAfterCarriageReturnKeepsTheCursorInside() {
        var text = "first line\r"
        let cursor = text.insertLineBreak(replacing: text.endIndex..<text.endIndex)
        #expect(text == "first line\r\n")
        #expect(cursor == text.endIndex)
    }

    @Test func breakAfterCarriageReturnMidText() {
        var text = "a\rb"
        let at = text.index(after: text.startIndex)
        let after = text.unicodeScalars.index(after: at)
        let cursor = text.insertLineBreak(replacing: after..<after)
        #expect(text == "a\r\nb")
        #expect(text[cursor...] == "b")
    }
}

extension TypedLineBreakTests {
    /// The field's cursor can outlive the draft it was in, after a send or a switch of chat.
    @Test func cursorPastTheEndAddsTheBreakAtTheEnd() {
        let old = "a much longer earlier draft"
        let stale = old.index(old.startIndex, offsetBy: 20)
        var text = "hi"
        let cursor = text.insertLineBreak(replacing: stale..<stale)
        #expect(text == "hi\n")
        #expect(cursor == text.endIndex)
    }
}
