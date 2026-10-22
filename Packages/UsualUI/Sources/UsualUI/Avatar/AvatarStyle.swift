import Foundation

/// Picks an agent's avatar colour and dot position. Both are derived from the contact ID with a
/// stable hash, so an agent looks the same on every launch and on every device.
public struct AvatarStyle: Equatable, Sendable {
    /// Centre of the white dot as a fraction of the avatar size; each agent gets one of these.
    public static let dotPositions: [DotPosition] = [
        DotPosition(x: 0.68, y: 0.32),
        DotPosition(x: 0.32, y: 0.32),
        DotPosition(x: 0.68, y: 0.68),
        DotPosition(x: 0.50, y: 0.25),
    ]

    public let paletteIndex: Int
    public let dot: DotPosition

    public init(seed: String, paletteCount: Int) {
        let hash = Self.fnv1a(seed)
        paletteIndex = Int(hash % UInt32(paletteCount))
        dot = Self.dotPositions[Int((hash >> 8) % UInt32(Self.dotPositions.count))]
    }

    /// 32-bit FNV-1a. Swift's `hashValue` is randomised per launch, so it can't be used here.
    static func fnv1a(_ string: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }
}

/// Where the white dot sits, as fractions of the avatar size.
public struct DotPosition: Equatable, Sendable {
    public let x: Double
    public let y: Double
}
