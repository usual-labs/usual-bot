import Foundation

/// An X keysym, the key a VNC key event names.
public struct Keysym: Equatable, Hashable, Sendable {
    public let value: UInt32

    public init(_ value: UInt32) {
        self.value = value
    }

    /// The key that types `character`: Latin-1 as itself, the rest of Unicode as `0x01000000 + code
    /// point`, and Return, Tab and Backspace for their control characters.
    public init?(character: Character) {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            if character == "\r\n" {
                self = .returnKey
                return
            }
            return nil
        }
        switch scalar.value {
        case 0x0A, 0x0D: self = .returnKey
        case 0x09: self = .tab
        case 0x08, 0x7F: self = .backspace
        case 0x20...0x7E, 0xA0...0xFF: self.init(scalar.value)
        case 0..<0x20: return nil
        default: self.init(0x0100_0000 + scalar.value)
        }
    }

    public static let returnKey = Keysym(0xFF0D)
    public static let tab = Keysym(0xFF09)
    public static let backspace = Keysym(0xFF08)
    public static let escape = Keysym(0xFF1B)
    public static let delete = Keysym(0xFFFF)
    public static let home = Keysym(0xFF50)
    public static let left = Keysym(0xFF51)
    public static let up = Keysym(0xFF52)
    public static let right = Keysym(0xFF53)
    public static let down = Keysym(0xFF54)
    public static let pageUp = Keysym(0xFF55)
    public static let pageDown = Keysym(0xFF56)
    public static let end = Keysym(0xFF57)
    public static let shift = Keysym(0xFFE1)
    public static let control = Keysym(0xFFE3)
    public static let alt = Keysym(0xFFE9)
    public static let superKey = Keysym(0xFFEB)

    /// F1 to F35.
    public static func function(_ number: Int) -> Keysym {
        Keysym(0xFFBE + UInt32(min(max(number, 1), 35) - 1))
    }
}
