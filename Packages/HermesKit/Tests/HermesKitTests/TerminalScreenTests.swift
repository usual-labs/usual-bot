import Foundation
import Testing

@testable import HermesKit

struct TerminalScreenTests {
    private func screen(_ output: String, columns: Int = 20, rows: Int = 5) -> TerminalScreen {
        var screen = TerminalScreen(columns: columns, rows: rows)
        screen.feed(output)
        return screen
    }

    @Test func printsLinesAndReturns() {
        let screen = screen("$ ls\r\na  b\r\n$ ")
        #expect(screen.text == "$ ls\na  b\n$")
        #expect(screen.cursorLine == 2)
        #expect(screen.cursorColumn == 2)
    }

    @Test func wrapsAtTheWidthOnlyWhenMoreIsPrinted() {
        var screen = screen("abcde", columns: 5)
        // The cursor waits on the last column, as a terminal's does, so `\r\n` doesn't add a blank line.
        #expect(screen.lines.count == 1)
        screen.feed("f")
        #expect(screen.text == "abcde\nf")
        screen = self.screen("abcde\r\nx", columns: 5)
        #expect(screen.text == "abcde\nx")
    }

    @Test func coloursComeInRuns() {
        let screen = screen("\u{1B}[1;32muser\u{1B}[0m:\u{1B}[38;5;33m~\u{1B}[38;2;1;2;3m$")
        let runs = screen.lines[0].runs
        #expect(runs.map(\.text) == ["user", ":", "~", "$"])
        #expect(runs[0].style.bold)
        #expect(runs[0].style.foreground == .palette(2))
        #expect(runs[1].style == TerminalScreen.Style())
        #expect(runs[2].style.foreground == .palette(33))
        #expect(runs[3].style.foreground == .rgb(1, 2, 3))
    }

    @Test func lineEditingRedrawsInPlace() {
        // What a shell sends for backspace, and for a history recall that's shorter than the line.
        var screen = screen("$ hello\u{8} \u{8}")
        #expect(screen.text == "$ hell")
        screen.feed("\r\u{1B}[K$ ls")
        #expect(screen.text == "$ ls")
        screen.feed("\u{1B}[2D\u{1B}[P")
        #expect(screen.text == "$ s")
        screen.feed("\u{1B}[1@")
        #expect(screen.text == "$  s")
    }

    @Test func clearMovesTheScreenIntoScrollback() {
        var screen = screen("one\r\ntwo\r\n")
        screen.feed("\u{1B}[H\u{1B}[2J$ ")
        #expect(screen.lines.first?.text == "one")
        #expect(screen.cursorLine == 2)
        #expect(screen.lines[screen.cursorLine].text == "$ ")
        screen.feed("\u{1B}[3J")
        #expect(screen.text == "$")
        #expect(screen.cursorLine == 0)
    }

    @Test func cursorAddressingIsWithinTheScreen() {
        var screen = screen("1\r\n2\r\n3\r\n4\r\n5\r\n6\r\n7", rows: 3)
        screen.feed("\u{1B}[1;1HX")
        #expect(screen.text == "1\n2\n3\n4\nX\n6\n7")
    }

    @Test func scrollbackIsCapped() {
        var screen = TerminalScreen(columns: 10, rows: 2, scrollback: 3)
        for line in 1...10 { screen.feed("\(line)\r\n") }
        #expect(screen.lines.count == 5)
        #expect(screen.lines.first?.text == "7")
        #expect(Set(screen.lines.map(\.id)).count == 5)
    }

    @Test func titlesAndModesPrintNothing() {
        var screen = screen("\u{1B}]0;user@host: ~\u{07}\u{1B}[?2004h\u{1B}[?25l\u{1B}(B$ ")
        #expect(screen.text == "$")
        #expect(screen.bracketedPaste)
        #expect(!screen.cursorVisible)
        screen.feed("\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\")
        #expect(screen.text == "$ link")
    }

    @Test func utf8SplitAcrossReadsPrintsOnce() {
        var screen = TerminalScreen()
        let bytes = Array("é✓🙂".utf8)
        screen.feed(Data(bytes[0..<1]))
        screen.feed(Data(bytes[1..<4]))
        screen.feed(Data(bytes[4...]))
        #expect(screen.text == "é✓🙂")
        screen.feed(Data([0xFF]))
        #expect(screen.text == "é✓🙂\u{FFFD}")
    }

    @Test func answersWhereTheCursorIs() {
        var screen = screen("ab\u{1B}[6n")
        #expect(screen.replies == [Data("\u{1B}[1;3R".utf8)])
    }
}
