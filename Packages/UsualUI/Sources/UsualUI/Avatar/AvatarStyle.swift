import Foundation

/// Picks an agent's character and colour. Both come from the contact ID with a stable hash, so an
/// agent looks the same on every launch and on every device.
public struct AvatarStyle: Equatable, Sendable {
    /// The 50 Usual Bot characters, in catalogue order (`design/avatars`). Each is the image
    /// `avatar-<slug>` in this package's resources.
    public static let characters = [
        "pip", "mallow", "rook", "tinker", "orbit", "moss", "quill", "nori", "pebble", "zippy",
        "tempo", "lumen", "bento", "fable", "tally", "echo", "patch", "sprocket", "puddle", "seal",
        "bramble", "dot", "kite", "tuck", "finch", "miso", "crumb", "wisp", "atlas", "doodle",
        "glint", "pogo", "sift", "knoll", "loop", "peris", "hush", "sprig", "toggle", "loom",
        "nova", "drift", "fizz", "puck", "stitch", "huddle", "nudge", "vellum", "riff", "mote",
    ]

    public let paletteIndex: Int
    public let character: String

    public init(seed: String, paletteCount: Int) {
        let hash = Self.fnv1a(seed)
        paletteIndex = Int(hash % UInt32(paletteCount))
        character = Self.characters[Int((hash >> 8) % UInt32(Self.characters.count))]
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
