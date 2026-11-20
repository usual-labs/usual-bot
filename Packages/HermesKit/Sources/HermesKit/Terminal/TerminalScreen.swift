import Foundation

/// What a shell has printed, as a terminal shows it: enough of VT100/xterm for a shell's prompt and
/// line editing (colours, cursor moves, erasing, wrapping at the width) and no more. Full-screen
/// programs (vim, top, less) ask for the alternate screen and scroll regions, which this ignores,
/// so they don't draw properly. The screen is the last `rows` lines; what scrolls off stays above
/// as scrollback, up to `scrollback` lines.
public struct TerminalScreen: Equatable, Sendable {
    public enum Color: Hashable, Sendable {
        /// The 256-colour palette: 0–7 normal, 8–15 bright, then the 6×6×6 cube and greys.
        case palette(UInt8)
        case rgb(UInt8, UInt8, UInt8)
    }

    public struct Style: Hashable, Sendable {
        public var foreground: Color?
        public var background: Color?
        public var bold = false
        public var dim = false
        public var italic = false
        public var underline = false
        public var inverse = false

        public init() {}
    }

    /// One stretch of a line in one style.
    public struct Run: Equatable, Sendable {
        public let text: String
        public let style: Style

        public init(text: String, style: Style) {
            self.text = text
            self.style = style
        }
    }

    public struct Line: Identifiable, Equatable, Sendable {
        /// Stable while the line is on screen or in scrollback, for SwiftUI.
        public let id: Int
        var characters: [Character] = []
        var styles: [Style] = []

        public var text: String { String(characters) }

        public var runs: [Run] {
            var runs: [Run] = []
            var start = 0
            while start < characters.count {
                var end = start + 1
                while end < characters.count, styles[end] == styles[start] { end += 1 }
                runs.append(Run(text: String(characters[start..<end]), style: styles[start]))
                start = end
            }
            return runs
        }
    }

    public private(set) var lines: [Line]
    public private(set) var columns: Int
    public private(set) var rows: Int
    /// The cursor: a line in `lines`, and a column.
    public private(set) var cursorLine = 0
    public private(set) var cursorColumn = 0
    public private(set) var cursorVisible = true
    /// The shell asked for bracketed paste (`?2004h`): pasted text goes between markers.
    public private(set) var bracketedPaste = false
    /// What the screen must answer the shell with (a cursor position report), for the caller to send.
    public internal(set) var replies: [Data] = []

    let scrollback: Int
    private var top = 0
    private var style = Style()
    private var pendingWrap = false
    private var saved: (line: Int, column: Int) = (0, 0)
    private var nextID = 1
    private var parser = Parser.ground
    private var parameters = ""
    private var utf8: [UInt8] = []

    private enum Parser: Equatable { case ground, escape, csi, osc, oscEscape, charset }

    public init(columns: Int = 80, rows: Int = 24, scrollback: Int = 5_000) {
        self.columns = max(columns, 2)
        self.rows = max(rows, 1)
        self.scrollback = scrollback
        lines = [Line(id: 0)]
    }

    public static func == (a: TerminalScreen, b: TerminalScreen) -> Bool {
        a.lines == b.lines && a.cursorLine == b.cursorLine && a.cursorColumn == b.cursorColumn
            && a.columns == b.columns && a.rows == b.rows && a.cursorVisible == b.cursorVisible
    }

    /// Everything, as plain text: for copying and for tests.
    public var text: String {
        var lines = lines.map { String($0.text.reversed().drop { $0 == " " }.reversed()) }
        while lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// A new size. Lines already printed keep their wrapping, as Terminal's do.
    public mutating func resize(columns: Int, rows: Int) {
        self.columns = max(columns, 2)
        self.rows = max(rows, 1)
        top = max(0, min(top, lines.count - 1))
        if cursorLine >= top + self.rows { top = cursorLine - self.rows + 1 }
        cursorColumn = min(cursorColumn, self.columns - 1)
        pendingWrap = false
    }

    // MARK: - Reading

    public mutating func feed(_ data: Data) {
        for byte in data { feed(byte) }
    }

    public mutating func feed(_ text: String) { feed(Data(text.utf8)) }

    private mutating func feed(_ byte: UInt8) {
        if !utf8.isEmpty || byte >= 0x80 {
            collect(byte)
            return
        }
        let scalar = Character(Unicode.Scalar(byte))
        switch parser {
        case .ground: ground(byte, scalar)
        case .escape: escape(byte, scalar)
        case .csi:
            if (0x30...0x3F).contains(byte) {
                parameters.append(scalar)
            } else if (0x40...0x7E).contains(byte) {
                parser = .ground
                csi(scalar)
                parameters = ""
            } else if byte == 0x1B {
                parser = .escape
                parameters = ""
            }
        case .osc:
            // A title or a link: shown nowhere.
            if byte == 0x07 { parser = .ground } else if byte == 0x1B { parser = .oscEscape }
        case .oscEscape: parser = byte == UInt8(ascii: "\\") ? .ground : .osc
        case .charset: parser = .ground
        }
    }

    /// Multi-byte UTF-8, printed once whole. A stray byte prints as �.
    private mutating func collect(_ byte: UInt8) {
        if utf8.isEmpty {
            guard (0xC2...0xF4).contains(byte) else { return put("\u{FFFD}") }
        } else if byte & 0xC0 != 0x80 {
            utf8 = []
            put("\u{FFFD}")
            return feed(byte)
        }
        utf8.append(byte)
        let needed = utf8[0] >= 0xF0 ? 4 : utf8[0] >= 0xE0 ? 3 : 2
        guard utf8.count == needed else { return }
        let text = String(decoding: utf8, as: UTF8.self)
        utf8 = []
        if parser == .ground, let character = text.first { put(character) }
    }

    private mutating func ground(_ byte: UInt8, _ character: Character) {
        switch byte {
        case 0x1B: parser = .escape
        case 0x0D:
            cursorColumn = 0
            pendingWrap = false
        case 0x0A, 0x0B, 0x0C: lineFeed()
        case 0x08:
            cursorColumn = max(0, cursorColumn - 1)
            pendingWrap = false
        case 0x09: cursorColumn = min(columns - 1, (cursorColumn / 8 + 1) * 8)
        case 0x20...0x7E: put(character)
        default: break  // BEL and the other controls
        }
    }

    private mutating func escape(_ byte: UInt8, _ character: Character) {
        parser = .ground
        switch character {
        case "[": parser = .csi
        case "]": parser = .osc
        case "(", ")", "*", "+": parser = .charset
        case "7": saved = (cursorLine, cursorColumn)
        case "8": (cursorLine, cursorColumn) = (min(saved.line, lines.count - 1), saved.column)
        case "D": lineFeed()
        case "E":
            cursorColumn = 0
            lineFeed()
        case "M": cursorLine = max(top, cursorLine - 1)
        case "c": self = TerminalScreen(columns: columns, rows: rows, scrollback: scrollback)
        default: break
        }
    }

    // MARK: - Control sequences

    private mutating func csi(_ final: Character) {
        let isPrivate = parameters.hasPrefix("?")
        let numbers = parameters.drop { $0 == "?" || $0 == ">" || $0 == "=" }
            .split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        func number(_ index: Int, _ fallback: Int = 1) -> Int {
            index < numbers.count ? (numbers[index].map { $0 == 0 ? fallback : $0 } ?? fallback) : fallback
        }
        if isPrivate {
            if final == "h" || final == "l" { privateMode(numbers.compactMap { $0 }, on: final == "h") }
            return
        }
        pendingWrap = false
        switch final {
        case "m": graphics(numbers.map { $0 ?? 0 })
        case "A": cursorLine = max(top, cursorLine - number(0))
        case "B", "e": moveDown(number(0))
        case "C", "a": cursorColumn = min(columns - 1, cursorColumn + number(0))
        case "D": cursorColumn = max(0, cursorColumn - number(0))
        case "E":
            moveDown(number(0))
            cursorColumn = 0
        case "F":
            cursorLine = max(top, cursorLine - number(0))
            cursorColumn = 0
        case "G", "`": cursorColumn = min(columns - 1, number(0) - 1)
        case "d": goTo(row: number(0) - 1, column: cursorColumn)
        case "H", "f": goTo(row: number(0) - 1, column: number(1) - 1)
        case "K": eraseInLine(numbers.first.flatMap { $0 } ?? 0)
        case "J": eraseInScreen(numbers.first.flatMap { $0 } ?? 0)
        case "P": deleteCharacters(number(0))
        case "@": insertBlanks(number(0))
        case "X": erase(from: cursorColumn, count: number(0))
        case "s": saved = (cursorLine, cursorColumn)
        case "u": (cursorLine, cursorColumn) = (min(saved.line, lines.count - 1), saved.column)
        case "n" where number(0) == 6:
            replies.append(Data("\u{1B}[\(cursorLine - top + 1);\(cursorColumn + 1)R".utf8))
        case "c" where parameters.isEmpty || parameters == "0":
            replies.append(Data("\u{1B}[?1;2c".utf8))
        default: break  // scroll regions, tabs stops, window ops
        }
    }

    private mutating func privateMode(_ modes: [Int], on: Bool) {
        for mode in modes {
            switch mode {
            case 25: cursorVisible = on
            case 2004: bracketedPaste = on
            default: break
            }
        }
    }

    private mutating func graphics(_ codes: [Int]) {
        var index = 0
        let codes = codes.isEmpty ? [0] : codes
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = Style()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22: (style.bold, style.dim) = (false, false)
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .palette(UInt8(code - 30))
            case 39: style.foreground = nil
            case 40...47: style.background = .palette(UInt8(code - 40))
            case 49: style.background = nil
            case 90...97: style.foreground = .palette(UInt8(code - 90 + 8))
            case 100...107: style.background = .palette(UInt8(code - 100 + 8))
            case 38, 48:
                var color: Color?
                if index + 2 < codes.count, codes[index + 1] == 5 {
                    color = .palette(UInt8(clamping: codes[index + 2]))
                    index += 2
                } else if index + 4 < codes.count, codes[index + 1] == 2 {
                    color = .rgb(
                        UInt8(clamping: codes[index + 2]), UInt8(clamping: codes[index + 3]),
                        UInt8(clamping: codes[index + 4]))
                    index += 4
                }
                if code == 38 { style.foreground = color } else { style.background = color }
            default: break
            }
            index += 1
        }
    }

    // MARK: - Writing

    private mutating func put(_ character: Character) {
        if pendingWrap {
            pendingWrap = false
            cursorColumn = 0
            lineFeed()
        }
        pad(cursorLine, to: cursorColumn + 1)
        lines[cursorLine].characters[cursorColumn] = character
        lines[cursorLine].styles[cursorColumn] = style
        if cursorColumn == columns - 1 { pendingWrap = true } else { cursorColumn += 1 }
    }

    private mutating func lineFeed() {
        pendingWrap = false
        cursorLine += 1
        if cursorLine == lines.count { appendLine() }
        if cursorLine >= top + rows { top = cursorLine - rows + 1 }
        trimScrollback()
    }

    private mutating func moveDown(_ count: Int) {
        cursorLine = min(cursorLine + count, top + rows - 1)
        while cursorLine >= lines.count { appendLine() }
    }

    private mutating func goTo(row: Int, column: Int) {
        cursorLine = top + min(max(row, 0), rows - 1)
        while cursorLine >= lines.count { appendLine() }
        cursorColumn = min(max(column, 0), columns - 1)
    }

    private mutating func appendLine() {
        lines.append(Line(id: nextID))
        nextID += 1
    }

    private mutating func trimScrollback() {
        let extra = lines.count - (scrollback + rows)
        guard extra > 0 else { return }
        lines.removeFirst(extra)
        cursorLine -= extra
        top = max(0, top - extra)
        saved.line = max(0, saved.line - extra)
    }

    private mutating func pad(_ line: Int, to count: Int) {
        let missing = count - lines[line].characters.count
        guard missing > 0 else { return }
        lines[line].characters += Array(repeating: " ", count: missing)
        lines[line].styles += Array(repeating: Style(), count: missing)
    }

    private mutating func eraseInLine(_ mode: Int) {
        var line = lines[cursorLine]
        switch mode {
        case 0:
            let keep = min(cursorColumn, line.characters.count)
            line.characters.removeSubrange(keep...)
            line.styles.removeSubrange(keep...)
        case 1:
            for index in 0..<min(cursorColumn + 1, line.characters.count) {
                line.characters[index] = " "
                line.styles[index] = Style()
            }
        default:
            line.characters = []
            line.styles = []
        }
        lines[cursorLine] = line
    }

    private mutating func eraseInScreen(_ mode: Int) {
        switch mode {
        case 0:
            eraseInLine(0)
            lines.removeSubrange((cursorLine + 1)...)
        case 1:
            for line in top..<cursorLine { (lines[line].characters, lines[line].styles) = ([], []) }
            eraseInLine(1)
        case 2:
            // `clear`: what was on screen moves up into the scrollback, as in Terminal.
            let row = cursorLine - top
            let used = lines.lastIndex { !$0.characters.isEmpty }.map { $0 + 1 } ?? 0
            lines.removeSubrange(used...)
            top = lines.count
            for _ in 0..<rows { appendLine() }
            cursorLine = top + row
            trimScrollback()
        default:
            // 3: the scrollback goes.
            lines.removeFirst(top)
            cursorLine -= top
            saved.line = max(0, saved.line - top)
            top = 0
        }
    }

    private mutating func deleteCharacters(_ count: Int) {
        guard cursorColumn < lines[cursorLine].characters.count else { return }
        let end = min(cursorColumn + count, lines[cursorLine].characters.count)
        lines[cursorLine].characters.removeSubrange(cursorColumn..<end)
        lines[cursorLine].styles.removeSubrange(cursorColumn..<end)
    }

    private mutating func insertBlanks(_ count: Int) {
        guard cursorColumn < lines[cursorLine].characters.count else { return }
        lines[cursorLine].characters.insert(contentsOf: Array(repeating: " ", count: count), at: cursorColumn)
        lines[cursorLine].styles.insert(contentsOf: Array(repeating: Style(), count: count), at: cursorColumn)
        if lines[cursorLine].characters.count > columns {
            lines[cursorLine].characters.removeSubrange(columns...)
            lines[cursorLine].styles.removeSubrange(columns...)
        }
    }

    private mutating func erase(from column: Int, count: Int) {
        let end = min(column + count, lines[cursorLine].characters.count)
        guard column < end else { return }
        for index in column..<end {
            lines[cursorLine].characters[index] = " "
            lines[cursorLine].styles[index] = Style()
        }
    }
}
