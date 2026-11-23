import Foundation

/// When you start and stop talking, from the microphone's loudness alone: a Gateway call has no
/// recognizer on the device to say so, and a gateway that can't stream sends no words until the
/// end. Speech is a run of loud samples; the turn ends after a quiet spell. Words from the
/// gateway, when they come, count as speech too.
struct TurnDetector {
    enum Event: Equatable {
        /// You started talking (or, while the Bot talks, talked over it).
        case started
        /// You stopped: the turn is over.
        case ended
    }

    /// Loudness, 0…1, that counts as a voice (about −30 dB).
    var threshold = 0.4
    /// How long a voice has to last to count: long enough that a cough or a click doesn't.
    var startAfter = Self.listenAfter
    /// The quiet that ends a turn; On-device calls wait as long after the last word.
    var endAfter: TimeInterval = 1.1

    static let listenAfter: TimeInterval = 0.15
    /// How long you must talk over the Bot to cut it off: longer, so a bit of its own voice that
    /// echo cancellation lets through doesn't.
    static let bargeInAfter: TimeInterval = 0.4

    private(set) var speaking = false
    private var loudSince: TimeInterval?
    private var lastVoice: TimeInterval = 0

    /// One loudness sample at `time` (seconds, any clock that only goes forward).
    mutating func heard(_ level: Double, at time: TimeInterval) -> Event? {
        if level >= threshold {
            lastVoice = time
            if speaking { return nil }
            let since = loudSince ?? time
            loudSince = since
            if time - since >= startAfter {
                speaking = true
                return .started
            }
            return nil
        }
        loudSince = nil
        if speaking, time - lastVoice >= endAfter {
            speaking = false
            return .ended
        }
        return nil
    }

    /// The gateway heard words at `time`: you're still talking.
    mutating func heardWords(at time: TimeInterval) {
        if speaking { lastVoice = max(lastVoice, time) }
    }

    /// Forgets everything: the next sample starts afresh.
    mutating func reset() {
        speaking = false
        loudSince = nil
    }
}
