import Foundation

extension String {
    /// Puts a line break in place of `range` and returns where the cursor goes after it.
    ///
    /// Counted in UTF-8, not characters: a break typed after "\r" (pasted Windows text) joins it
    /// into one character, so the text gains no character and a character count lands past the end.
    /// A range that isn't inside this text, such as a cursor left from an earlier draft, adds the
    /// break at the end.
    mutating func insertLineBreak(replacing range: Range<Index>) -> Index {
        guard range.lowerBound >= startIndex, range.upperBound <= endIndex else {
            append("\n")
            return endIndex
        }
        let offset = utf8.distance(from: startIndex, to: range.lowerBound) + 1
        replaceSubrange(range, with: "\n")
        return utf8.index(startIndex, offsetBy: offset)
    }
}
