import Foundation
import Testing

@testable import UsualUI

struct RGBTests {
    @Test func parsesHexWithAndWithoutHash() {
        #expect(RGB(hex: "#FF8000") == RGB(0xFF8000))
        #expect(RGB(hex: "ff8000") == RGB(0xFF8000))
        #expect(RGB(0xFF8000).red == 1)
        #expect(RGB(0xFF8000).blue == 0)
    }

    @Test func parsesCSSHSLAsHermesStoresIt() throws {
        // hsl(0 100% 50%) is pure red; hsl(120, 100%, 25%) is #008000.
        #expect(RGB(css: "hsl(0 100% 50%)") == RGB(0xFF0000))
        let green = try #require(RGB(css: "hsla(120, 100%, 25%, 0.5)"))
        #expect(abs(green.green - 0.5) < 0.001 && green.red == 0 && green.blue == 0)
        // The colour Hermes gave a real bot: a light cyan.
        let cyan = try #require(RGB(css: "hsl(180 68% 58%)"))
        #expect(abs(cyan.red - 0.2944) < 0.001 && abs(cyan.green - 0.8656) < 0.001 && cyan.green == cyan.blue)
        #expect(RGB(css: "#6E7BFF") == RGB(0x6E7BFF))
    }

    @Test func rejectsUnknownCSS() {
        #expect(RGB(css: "rebeccapurple") == nil)
        #expect(RGB(css: "hsl(180 68 58)") == nil)
        #expect(RGB(css: "hsl(180 68%)") == nil)
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

    @Test func staysInsidePaletteAndCharacters() {
        for seed in ["hermes", "scout", "ops", "writer", "", "a-much-longer-profile-name"] {
            let style = AvatarStyle(seed: seed, paletteCount: 6)
            #expect((0..<6).contains(style.paletteIndex))
            #expect(AvatarStyle.characters.contains(style.character))
        }
    }

    @Test func everyCharacterHasAnImage() {
        #expect(AvatarStyle.characters.count == 50)
        #expect(Set(AvatarStyle.characters).count == 50)
        for character in AvatarStyle.characters {
            #expect(
                Bundle.module.url(forResource: "avatar-\(character)", withExtension: "png") != nil,
                "missing avatar-\(character).png")
        }
    }
}
