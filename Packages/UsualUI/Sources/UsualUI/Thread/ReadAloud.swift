import AVFoundation
import Observation

/// Says sentences aloud. The device's voice in the app; a silent one in tests.
@MainActor
protocol ReadingVoice: AnyObject {
    /// Says `sentences` in turn, then calls `finished`, unless `stop` came first.
    func speak(_ sentences: [String], finished: @escaping @MainActor () -> Void)
    func stop()
}

/// Reads a message aloud with the on-device voice from Settings › Voice. One message at a time,
/// never together with the chat's player (`MediaPlayback`), and not during a call.
@MainActor @Observable
final class ReadAloud {
    static let shared = ReadAloud(playback: .shared)

    /// The message being read (see `key(scope:chat:item:)`), or `nil`.
    private(set) var key: String?
    /// Calls running now. A call has the microphone, which would hear the reading.
    private var calls = 0
    var inCall: Bool { calls > 0 }

    @ObservationIgnored private let voice: any ReadingVoice
    @ObservationIgnored private weak var playback: MediaPlayback?
    /// Which reading is current, so one that ended late doesn't end the next.
    @ObservationIgnored private var token = 0

    init(playback: MediaPlayback, voice: any ReadingVoice = DeviceVoice()) {
        self.playback = playback
        self.voice = voice
        // The player tells the reading, so every place that plays or leaves a chat is covered.
        playback.willPlay = { [weak self] in self?.stop() }
        playback.left = { [weak self] scope in self?.stop(in: scope) }
    }

    /// Reads `markdown` as words, in place of whatever was read or played before.
    func read(_ markdown: String, key: String) {
        stop()
        var reply = SpokenReply()
        let sentences = reply.sentences(in: markdown, final: true)
        guard !inCall, !sentences.isEmpty else { return }
        playback?.pause()
        MediaPlayback.activateAudioSession()
        token += 1
        self.key = key
        voice.speak(sentences) { [weak self, token] in
            guard let self, self.token == token else { return }
            self.key = nil
            self.releaseAudioSession()
        }
    }

    func stop() {
        guard key != nil else { return }
        token += 1
        key = nil
        voice.stop()
        releaseAudioSession()
    }

    /// Stops what's read in `scope` (see `playbackScope`), as when you leave the chat.
    func stop(in scope: String) {
        if key?.hasPrefix(scope + "\u{0}") == true { stop() }
    }

    func callStarted() {
        calls += 1
        stop()
    }

    func callEnded() { calls = max(calls - 1, 0) }

    /// A key for a message shown in `scope`.
    static func key(scope: String, chat: String, item: Int) -> String {
        [scope, chat, String(item)].joined(separator: "\u{0}")
    }

    /// A voice memo that took over keeps the session.
    private func releaseAudioSession() {
        if playback?.isPlaying != true { MediaPlayback.releaseAudioSession() }
    }
}

/// The on-device voice, with the language, voice and speed chosen in Settings › Voice.
@MainActor
final class DeviceVoice: NSObject, ReadingVoice, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var last: ObjectIdentifier?
    private var finished: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ sentences: [String], finished: @escaping @MainActor () -> Void) {
        stop()
        self.finished = finished
        for sentence in sentences {
            let utterance = CallSettings.utterance(sentence)
            last = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        finished = nil
        last = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let done = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard done == last else { return }
            let finished = finished
            self.finished = nil
            last = nil
            finished?()
        }
    }
}
