import AVFoundation
import Observation

/// The app's one player for audio and video in chats, so starting one stops whatever played
/// before. Views ask for it by key (the message and file) and show its state when it's theirs.
@MainActor @Observable
final class MediaPlayback {
    static let shared = MediaPlayback()

    /// Which file is loaded, or `nil` when nothing is.
    private(set) var key: String?
    private(set) var isPlaying = false
    /// Seconds into the file. Read it only while the file is yours: it changes ten times a second.
    private(set) var elapsed: TimeInterval = 0
    /// Voice memo speed: 1, 1.5 or 2.
    private(set) var rate: Float = 1
    /// The last file that turned out not to play.
    private(set) var failedKey: String?

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    init() {
        player.actionAtItemEnd = .pause
        // Formed in a nonisolated context: these run on framework queues (see known issues).
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main, using: Self.onTick(self))
        statusObservation = player.observe(\.timeControlStatus, changeHandler: Self.onStatus(self))
        itemObservation = player.observe(\.currentItem?.status, changeHandler: Self.onItemStatus(self))
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main,
            using: Self.onEnd(self))
    }

    func isCurrent(_ key: String) -> Bool { self.key == key }

    /// Plays `url` from where it was, or from the start if another file was loaded.
    func play(_ url: URL, key: String, at speed: Float = 1) {
        if failedKey == key { failedKey = nil }
        if self.key != key {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            self.key = key
            elapsed = 0
        }
        rate = speed
        Self.activateAudioSession()
        player.playImmediately(atRate: speed)
    }

    func pause() { player.pause() }

    func seek(to seconds: TimeInterval) {
        elapsed = max(0, seconds)
        player.seek(
            to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ speed: Float) {
        rate = speed
        if isPlaying { player.rate = speed }
    }

    /// Unloads the file, as when you leave the chat.
    func stop() {
        guard key != nil else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        key = nil
        elapsed = 0
        isPlaying = false
        #if os(iOS)
            // Lets music another app was playing carry on.
            if AVAudioSession.sharedInstance().category == .playback {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        #endif
    }

    /// Stops what plays in `scope` (see `playbackScope`), and leaves the rest playing.
    func stop(in scope: String) {
        if key?.hasPrefix(scope + "\u{0}") == true { stop() }
    }

    /// A key for a file shown in `scope`, as `profile` reads it.
    static func key(scope: String, profile: String?, path: String) -> String {
        [scope, profile ?? "", path].joined(separator: "\u{0}")
    }

    nonisolated private static func onTick(_ playback: MediaPlayback) -> @Sendable (CMTime) -> Void {
        { [weak playback] time in
            MainActor.assumeIsolated {
                guard let playback, playback.key != nil, time.isNumeric else { return }
                playback.elapsed = time.seconds
            }
        }
    }

    nonisolated private static func onStatus(
        _ playback: MediaPlayback
    ) -> @Sendable (AVPlayer, NSKeyValueObservedChange<AVPlayer.TimeControlStatus>) -> Void {
        { [weak playback] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in playback?.isPlaying = playing }
        }
    }

    nonisolated private static func onItemStatus(
        _ playback: MediaPlayback
    ) -> @Sendable (AVPlayer, NSKeyValueObservedChange<AVPlayerItem.Status?>) -> Void {
        { [weak playback] player, _ in
            guard player.currentItem?.status == .failed else { return }
            Task { @MainActor in
                guard let playback, let key = playback.key else { return }
                playback.stop()
                playback.failedKey = key
            }
        }
    }

    nonisolated private static func onEnd(_ playback: MediaPlayback) -> @Sendable (Notification) -> Void {
        { [weak playback] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                // Back to the start, still loaded: a video keeps its controls, so it can play again
                // or leave full screen on its own.
                guard let playback, let item, item === playback.player.currentItem else { return }
                playback.player.pause()
                playback.seek(to: 0)
            }
        }
    }

    /// On iPhone, plays through the speaker even with the ring switch on silent, as a voice
    /// message would. A call or dictation that has the microphone keeps its own setup.
    private static func activateAudioSession() {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            guard session.category != .playAndRecord, session.category != .record else { return }
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
        #endif
    }
}
