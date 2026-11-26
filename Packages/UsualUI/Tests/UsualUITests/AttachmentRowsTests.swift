import CoreGraphics
import Testing

@testable import UsualUI

struct AttachmentRowsTests {
    @Test func tilesThatFitShareOneRow() {
        let widths: [CGFloat] = [64, 64, 64, 64]
        #expect(AttachmentRows.rows(widths, in: 300, spacing: 6) == [[0, 1, 2, 3]])
    }

    /// Four photos that couldn't load show by name, each about 230 points wide: on an iPhone they
    /// used to stay in one row and widen the whole conversation past the screen.
    @Test func tilesTooWideForOneRowWrap() {
        let widths: [CGFloat] = [230, 230, 64, 230]
        #expect(AttachmentRows.rows(widths, in: 330, spacing: 6) == [[0], [1, 2], [3]])
    }

    @Test func aTileWiderThanTheRowGetsOneToItself() {
        #expect(AttachmentRows.rows([400, 64], in: 300, spacing: 6) == [[0], [1]])
    }
}
