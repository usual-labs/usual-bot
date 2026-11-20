#if os(macOS)
    import AppKit
    import HermesKit
    import SwiftUI

    /// The terminal drawer's look. It stays dark in light mode too, as most terminals do: shells
    /// colour their output for a dark background, and yellow or white on white can't be read.
    enum TerminalStyle {
        static let background = Color(hex: 0x141416)
        static let bar = Color(hex: 0x1B1B1E)
        static let divider = Color(hex: 0x2A2A2F)
        static let ink = Color(hex: 0xD8D8DC)
        static let secondaryInk = Color(hex: 0x8A8A93)
        static let selectedTab = Color(hex: 0x2A2A30)
        static let fontSize: CGFloat = 12
        static let padding: CGFloat = 10

        static func font(size: CGFloat, bold: Bool = false) -> NSFont {
            .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        }

        /// One character's width and one line's height at `size`: how many fit is the shell's size.
        static func cell(size: CGFloat) -> CGSize {
            let font = font(size: size)
            let width = ("M" as NSString).size(withAttributes: [.font: font]).width
            return CGSize(width: width, height: ceil(font.ascender - font.descender + font.leading))
        }

        /// xterm's 16 colours, then the 6×6×6 cube and the greys.
        static func color(_ color: TerminalScreen.Color) -> Color {
            switch color {
            case .rgb(let red, let green, let blue):
                return Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
            case .palette(let index):
                if index < 16 { return Color(hex: basic[Int(index)]) }
                if index >= 232 {
                    let level = Double(8 + Int(index - 232) * 10) / 255
                    return Color(red: level, green: level, blue: level)
                }
                let cube = Int(index) - 16
                func level(_ value: Int) -> Double { value == 0 ? 0 : Double(55 + value * 40) / 255 }
                return Color(red: level(cube / 36), green: level(cube / 6 % 6), blue: level(cube % 6))
            }
        }

        private static let basic: [UInt32] = [
            0x2E2E33, 0xF0626A, 0x7EE787, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xD8D8DC,
            0x6E6E78, 0xFF8A8F, 0xA5F0AB, 0xF2CC60, 0xA5D6FF, 0xE2C5FF, 0x88E5EB, 0xFFFFFF,
        ]

        /// A line of the screen as text, with the cursor drawn as a block at `cursor`.
        static func text(_ line: TerminalScreen.Line, cursor: Int?, size: CGFloat) -> AttributedString {
            var runs = line.runs
            if let cursor {
                let width = runs.reduce(0) { $0 + $1.text.count }
                if cursor >= width {
                    runs.append(.init(text: String(repeating: " ", count: cursor - width + 1), style: .init()))
                }
            }
            var result = AttributedString()
            var column = 0
            for run in runs {
                let characters = Array(run.text)
                if let cursor, (column..<column + characters.count).contains(cursor) {
                    let at = cursor - column
                    var inverted = run.style
                    inverted.inverse.toggle()
                    result += piece(String(characters[..<at]), run.style, size)
                    result += piece(String(characters[at]), inverted, size)
                    result += piece(String(characters[(at + 1)...]), run.style, size)
                } else {
                    result += piece(run.text, run.style, size)
                }
                column += characters.count
            }
            return result
        }

        private static func piece(_ text: String, _ style: TerminalScreen.Style, _ size: CGFloat) -> AttributedString {
            var piece = AttributedString(text)
            apply(style, to: &piece, size: size)
            return piece
        }

        private static func apply(_ style: TerminalScreen.Style, to text: inout AttributedString, size: CGFloat) {
            var foreground = style.foreground.map(color) ?? ink
            var background = style.background.map(color)
            if style.bold, case .palette(let index) = style.foreground, index < 8 {
                foreground = color(.palette(index + 8))
            }
            if style.inverse {
                let swapped = background ?? TerminalStyle.background
                background = foreground
                foreground = swapped
            }
            text.font = Font(font(size: size, bold: style.bold))
            text.foregroundColor = style.dim ? foreground.opacity(0.6) : foreground
            if let background { text.backgroundColor = background }
            if style.italic { text.inlinePresentationIntent = .emphasized }
            if style.underline { text.underlineStyle = .single }
        }
    }

#endif
