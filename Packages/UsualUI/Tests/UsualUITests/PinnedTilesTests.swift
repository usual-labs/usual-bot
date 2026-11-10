import Testing

@testable import UsualUI

struct PinnedTilesTests {
    private func fit(_ count: Int, in width: Double) -> (perRow: Int, tileWidth: Double) {
        let fit = TileRows.fit(count, in: width, minWidth: 76, maxWidth: 94, spacing: 4)
        return (fit.perRow, Double(fit.tileWidth))
    }

    @Test func aFewTilesKeepTheirWidestAndDontStretch() {
        #expect(fit(1, in: 260) == (1, 94))
        #expect(fit(2, in: 260) == (2, 94))
    }

    @Test func aFullRowSharesTheWidth() {
        #expect(fit(3, in: 260) == (3, 84))
    }

    @Test func moreThanFitWrapAtTheSameWidth() {
        #expect(fit(7, in: 260) == (3, 84))
    }

    @Test func aRowTooNarrowForOneStillTakesOne() {
        #expect(fit(2, in: 60) == (1, 60))
    }
}
