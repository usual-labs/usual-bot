import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// The app's colours: a near-black window in dark mode, with each surface a step lighter than the
/// one behind it.
public enum Theme {
    /// Window background behind the sidebar and the chat pane.
    public static let window = Color(light: 0xF5F5F5, dark: 0x101010)
    /// The chat pane.
    public static let pane = Color(light: 0xFFFFFF, dark: 0x161616)
    /// The agent's bubbles and the cards in a conversation.
    static let bubble = Color(light: 0xF0F0F0, dark: 0x252525)
    /// What floats over a conversation: the message box, the name pill and their kin.
    static let surface = Color(light: 0xFFFFFF, dark: 0x1F1F1F)
    /// Chat text: 15 pt on the Mac, 16 pt on iPhone, which is held further from the eye.
    #if os(macOS)
        static let messageSize: CGFloat = 15
    #else
        static let messageSize: CGFloat = 16
    #endif
    /// The widest a message or card grows, so lines stay readable in a wide window.
    static let bubbleWidth: CGFloat = 560
    public static let border = Color(light: 0xE6E6E6, dark: 0x2E2E2E)
    public static let ink = Color(light: 0x1C1C1C, dark: 0xF2F2F2)
    public static let secondaryInk = Color(light: 0x6B6B6B, dark: 0x9E9E9E)
    /// The selected contact row in the sidebar.
    public static let selection = Color(light: 0xEBEBEB, dark: 0x2A2A2A)
    /// Primary buttons and unread badges.
    public static let primary = Color(light: 0x1C1C1C, dark: 0xF2F2F2)
    public static let primaryInk = Color(light: 0xFFFFFF, dark: 0x1C1C1C)
    /// Your bubbles where there's no one agent's colour to use, as in rooms.
    public static let userBubble = Color(light: 0x1C1C1C, dark: 0x3A3A3A)
    public static let userBubbleInk = Color(light: 0xFFFFFF, dark: 0xF2F2F2)
    public static let needsYouFill = Color(light: 0xFFF1D6, dark: 0x3A2A0A)
    public static let needsYouInk = Color(light: 0x8A5300, dark: 0xF5C36B)
    public static let danger = Color(light: 0xB42318, dark: 0xF97066)
    /// Code blocks, which sit on a bubble, and the expanded tool-step list.
    public static let codeFill = Color(light: 0xFAFAFA, dark: 0x1A1A1A)
    public static let online = Color(hex: 0x1FA971)

    /// Avatar colours for agents whose profile doesn't set one.
    static let agentColors: [RGB] = [0x6E7BFF, 0x1FA971, 0xF2A30F, 0xF0565E, 0x8B5CF6, 0x0EA5E9].map(RGB.init)
    public static let agentPalette = agentColors.map(Color.init)
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

    /// The contrast of white text on this colour, from 1 to 21. Text wants at least 4.5.
    var contrastWithWhite: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return 1.05 / (luminance + 0.05)
    }

    /// This colour, darkened only as far as white text on it needs. Agents' colours can be anything,
    /// yellow included.
    var readableUnderWhite: RGB {
        var rgb = self
        while rgb.contrastWithWhite < 4.5 {
            rgb = RGB(red: rgb.red * 0.96, green: rgb.green * 0.96, blue: rgb.blue * 0.96)
        }
        return rgb
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

extension View {
    /// The surface of what floats over a conversation, the name pill and the message box: solid, so
    /// text passing behind stays out of the way, with a hairline border and a soft shadow.
    func floatingSurface(in shape: some InsettableShape) -> some View {
        background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
    }

}
