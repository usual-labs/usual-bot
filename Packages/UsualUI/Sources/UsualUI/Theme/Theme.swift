import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// The app's colours. Light values match the mockups; dark values keep the same hierarchy.
public enum Theme {
    /// Window background behind the sidebar and the chat pane.
    public static let window = Color(light: 0xF6F6F7, dark: 0x161618)
    /// The chat pane and other raised surfaces.
    public static let pane = Color(light: 0xFFFFFF, dark: 0x1E1E20)
    public static let border = Color(light: 0xE4E4E7, dark: 0x2E2E32)
    public static let ink = Color(light: 0x18181B, dark: 0xF2F2F3)
    public static let secondaryInk = Color(light: 0x66666E, dark: 0xA0A0A8)
    /// The selected contact row in the sidebar.
    public static let selection = Color(light: 0xEBEBEE, dark: 0x2A2A2E)
    /// Your own message bubbles, and primary buttons.
    public static let userBubble = Color(light: 0x18181B, dark: 0xF2F2F3)
    public static let userBubbleInk = Color(light: 0xFFFFFF, dark: 0x18181B)
    public static let needsYouFill = Color(light: 0xFFF1D6, dark: 0x3A2A0A)
    public static let needsYouInk = Color(light: 0x8A5300, dark: 0xF5C36B)
    public static let danger = Color(light: 0xB42318, dark: 0xF97066)
    public static let online = Color(hex: 0x1FA971)

    /// Avatar colours for agents whose profile doesn't set one.
    public static let agentPalette: [Color] = [
        Color(hex: 0x6E7BFF),
        Color(hex: 0x1FA971),
        Color(hex: 0xF2A30F),
        Color(hex: 0xF0565E),
        Color(hex: 0x8B5CF6),
        Color(hex: 0x0EA5E9),
    ]
}

/// A parsed colour, kept separate from `Color` so it can be tested.
public struct RGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ value: UInt32) {
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Accepts `#RRGGBB` or `RRGGBB`; returns `nil` for anything else.
    public init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespaces))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(value)
    }

    /// The CSS colours Hermes stores for bots: `#RRGGBB`, or `hsl()` / `hsla()` in either the
    /// space-separated (`hsl(180 68% 58%)`) or comma-separated (`hsl(180, 68%, 58%)`) form.
    /// Alpha is ignored. Returns `nil` for anything else.
    public init?(css: String) {
        let text = css.trimmingCharacters(in: .whitespaces).lowercased()
        if let rgb = RGB(hex: text) {
            self = rgb
            return
        }
        guard text.hasPrefix("hsl"), let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let inner = text[text.index(after: open)..<text.index(before: text.endIndex)]
        let parts = inner.split(whereSeparator: { " ,/".contains($0) }).map(String.init)
        guard parts.count >= 3,
            let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
            parts[1].hasSuffix("%"), let saturation = Double(parts[1].dropLast()),
            parts[2].hasSuffix("%"), let lightness = Double(parts[2].dropLast())
        else { return nil }
        self.init(hue: hue, saturation: saturation / 100, lightness: lightness / 100)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let s = min(max(saturation, 0), 1)
        let l = min(max(lightness, 0), 1)
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        func channel(_ offset: Double) -> Double {
            let k = (offset + h * 12).truncatingRemainder(dividingBy: 12)
            return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1))
        }
        self.init(red: channel(0), green: channel(8), blue: channel(4))
    }
}

extension Color {
    public init(hex: UInt32) {
        self.init(RGB(hex))
    }

    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// A colour that follows the system light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        let lightRGB = RGB(light)
        let darkRGB = RGB(dark)
        #if canImport(AppKit)
            self.init(
                nsColor: NSColor(name: nil) { appearance in
                    let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkRGB : lightRGB
                    return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
                })
        #else
            self.init(
                uiColor: UIColor { traits in
                    let rgb = traits.userInterfaceStyle == .dark ? darkRGB : lightRGB
                    return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
                })
        #endif
    }
}
