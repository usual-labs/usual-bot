import Foundation

extension MarkdownBlock {
    /// Turns each single line break in a reply into a hard break, so a line per item shows as one.
    /// CommonMark joins such lines into one paragraph, but agents write them for platforms that
    /// show them, and the gateway sends them as written. Blank lines still make paragraphs.
    ///
    /// Done with two trailing spaces, CommonMark's own hard break, which the parser ignores at the
    /// end of a block: list items, headings, table rows and fences need no special case. Only code
    /// keeps its lines as they are, since the spaces would be part of it.
    static func keepingLineBreaks(_ lines: [Substring]) -> String {
        var result: [Substring] = []
        var fence: Character?
        var inIndentedCode = false
        for (index, line) in lines.enumerated() {
            // A fence may sit in a quote or a list item.
            let trimmed = line.drop { $0 == " " || $0 == ">" }
            if let open = fence {
                if trimmed.hasPrefix(String(repeating: open, count: 3)) { fence = nil }
                result.append(line)
                continue
            }
            if let mark = trimmed.first, mark == "`" || mark == "~",
                trimmed.hasPrefix(String(repeating: mark, count: 3))
            {
                fence = mark
                result.append(line)
                continue
            }
            let isBlank = line.allSatisfy(\.isWhitespace)
            // Indented code can't interrupt a paragraph, so it starts after a blank line.
            let previousIsBlank = index == 0 || lines[index - 1].allSatisfy(\.isWhitespace)
            if !isBlank { inIndentedCode = isIndented(line) && (inIndentedCode || previousIsBlank) }
            let next = lines.index(after: index)
            let breaks = !isBlank && !inIndentedCode && next < lines.count && !lines[next].allSatisfy(\.isWhitespace)
            guard breaks else {
                result.append(line)
                continue
            }
            let words = line.reversed().drop { $0 == " " || $0 == "\t" }
            // An odd run of backslashes is already a hard break.
            if words.prefix { $0 == "\\" }.count % 2 == 1 {
                result.append(line)
            } else {
                result.append(Substring(String(words.reversed())) + "  ")
            }
        }
        return result.joined(separator: "\n")
    }

    /// Four columns in, a tab reaching the next multiple of four: deep enough for indented code.
    private static func isIndented(_ line: Substring) -> Bool {
        var column = 0
        for character in line {
            if character == " " {
                column += 1
            } else if character == "\t" {
                column += 4 - column % 4
            } else {
                break
            }
            if column >= 4 { return true }
        }
        return false
    }
}
