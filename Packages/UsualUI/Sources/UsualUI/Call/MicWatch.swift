import Foundation

/// Notices a call's microphone stopping under it. iOS stops an audio engine on an interruption or
/// a configuration change (a new route, voice processing settling in), and nothing tells the
/// tap: the call showed Listening with the microphone off. Seen on an iPhone a few seconds into
/// Gateway calls.
struct MicWatch: Sendable {
    enum Action: Equatable {
        case fine
        /// Start the engine again.
        case restart
        /// Starting again hasn't worked: end the call.
        case giveUp
    }

    /// How long without a buffer counts as stopped; they come about every 20 ms.
    static let silence: TimeInterval = 1
    /// Restarts in a row, with nothing heard between, before giving up.
    static let restarts = 3

    private var lastBuffer: TimeInterval
    private var lastRestart: TimeInterval?
    private var failedRestarts = 0

    init(at time: TimeInterval) {
        lastBuffer = time
    }

    /// The microphone gave audio at `time` (seconds on a clock that only goes forward).
    mutating func heardBuffer(at time: TimeInterval) {
        lastBuffer = time
        lastRestart = nil
        failedRestarts = 0
    }

    mutating func check(running: Bool, at time: TimeInterval) -> Action {
        guard !running || time - lastBuffer >= Self.silence else { return .fine }
        // A restart gets a moment to bring audio back before the next.
        if let lastRestart, time - lastRestart < Self.silence { return .fine }
        guard failedRestarts < Self.restarts else { return .giveUp }
        failedRestarts += 1
        lastRestart = time
        return .restart
    }
}
