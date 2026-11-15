import SwiftUI
import Testing

@testable import UsualUI

struct ZoomTests {
    @Test func zoomStepsStopAtTheEnds() {
        #expect(Zoom.percent(Zoom.actualSize) == "100%")
        #expect(Zoom.zoomedIn(Zoom.actualSize) == Zoom.actualSize + 1)
        let largest = Zoom.levels.count - 1
        #expect(Zoom.zoomedIn(largest) == largest)
        #expect(!Zoom.canZoomIn(largest))
        #expect(Zoom.zoomedOut(0) == 0)
        #expect(!Zoom.canZoomOut(0))
        // A level from a later or earlier version stays in range.
        #expect(Zoom.size(99) == Zoom.levels.last)
        #expect(Zoom.size(-3) == Zoom.levels.first)
    }

    @Test func levelsGrowInOrder() {
        let factors = Zoom.levels.map(Zoom.factor)
        #expect(factors == factors.sorted())
        #expect(Set(factors).count == factors.count)
        #expect(Zoom.factor(Zoom.size(Zoom.actualSize)) == 1)
    }

    /// The Mac's old Chat text size picks the level that keeps text about as large.
    @Test func chatTextSizeCarriesOverToTheZoom() {
        #expect(Zoom.percent(Zoom.initialLevel(chatTextSize: 0)) == "100%")
        #expect(Zoom.percent(Zoom.initialLevel(chatTextSize: -2)) == "90%")
        #expect(Zoom.percent(Zoom.initialLevel(chatTextSize: 3)) == "125%")
        #expect(Zoom.percent(Zoom.initialLevel(chatTextSize: 6)) == "150%")
    }

    #if os(macOS)
        @Test func macLengthsAndTextGrowWithTheZoom() {
            #expect(Theme.zoomed(560, for: .xxLarge) == 700)
            #expect(Theme.scaled(15, for: .xxxLarge) == 22.5)
            #expect(Theme.scaled(15, for: .large) == 15)
        }
    #endif
}
