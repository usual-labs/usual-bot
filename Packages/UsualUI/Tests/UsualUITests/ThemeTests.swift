import Testing

@testable import UsualUI

struct RGBTests {
    @Test func parsesHexWithAndWithoutHash() {
        #expect(RGB(hex: "#FF8000") == RGB(0xFF8000))
        #expect(RGB(hex: "ff8000") == RGB(0xFF8000))
        #expect(RGB(0xFF8000).red == 1)
        #expect(RGB(0xFF8000).blue == 0)
    }

    @Test func rejectsMalformedHex() {
        #expect(RGB(hex: "") == nil)
        #expect(RGB(hex: "#FFF") == nil)
        #expect(RGB(hex: "#GG0000") == nil)
        #expect(RGB(hex: "#FF000000") == nil)
    }
}

struct AvatarStyleTests {
    @Test func isStableForTheSameSeed() {
        // FNV-1a reference value: the style must not change between launches or devices.
        #expect(AvatarStyle.fnv1a("hermes") == AvatarStyle.fnv1a("hermes"))
        #expect(AvatarStyle.fnv1a("") == 0x811C_9DC5)
        #expect(AvatarStyle.fnv1a("a") == 0xE40C_292C)
    }

    @Test func staysInsidePalette() {
        for seed in ["hermes", "scout", "ops", "writer", "", "a-much-longer-profile-name"] {
            let style = AvatarStyle(seed: seed, paletteCount: 6)
            #expect((0..<6).contains(style.paletteIndex))
            #expect(AvatarStyle.dotPositions.contains(style.dot))
        }
    }
}
