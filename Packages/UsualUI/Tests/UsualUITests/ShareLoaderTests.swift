import Foundation
import Testing

@testable import UsualUI

struct ShareLoaderTests {
    @Test func aSharedFileKeepsTheNameYouKnowItBy() {
        // Photos hands over a copy named by an ID, and suggests the photo's own name.
        let copy = URL(filePath: "/tmp/8F2C-91AB.jpeg")
        #expect(ShareLoader.name(for: copy, suggested: "IMG_0042") == "IMG_0042.jpeg")
        #expect(ShareLoader.name(for: copy, suggested: "IMG_0042.JPEG") == "IMG_0042.JPEG")
        #expect(ShareLoader.name(for: copy, suggested: nil) == "8F2C-91AB.jpeg")
        #expect(ShareLoader.name(for: copy, suggested: "  ") == "8F2C-91AB.jpeg")
        #expect(ShareLoader.name(for: URL(filePath: "/tmp/notes"), suggested: "Notes") == "Notes")
    }
}
