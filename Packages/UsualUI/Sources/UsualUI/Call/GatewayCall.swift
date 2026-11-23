import AVFoundation
import HermesKit
import Observation
import os

/// A call through the Bot's own speech providers on Hermes (its `stt` and `tts` settings, the
/// `chained` voice mode): the device hears when you start and stop talking, the gateway turns
/// what you said into words, the words go to the chat as a message, and the reply comes back in
/// the gateway's voice, sentence by sentence as it's written. Speak over it to cut it off. Your
/// voice leaves the device, and the providers may bill the gateway's owner.
@MainActor
@Observable
final class GatewayCall: CallEngine {
    private(set) var phase = VoiceCall.Phase.starting
    private(set) var transcript: [VoiceCall.Line] = []
    /// What the gateway has heard of your turn so far, when it can stream words.
    private(set) var heard = ""
    private(set) var levels = [Double](repeating: 0, count: 14)
    var muted = false {
        didSet { audio?.setMuted(muted) }
    }

    let thread: ChatThread
    @ObservationIgnored private let profile: String
    @ObservationIgnored private let transcriber: GatewayTranscriber
    @ObservationIgnored private let speaker: GatewaySpeaker
    @ObservationIgnored private var audio: CallAudio?
    @ObservationIgnored private let tap = TurnTap()
    @ObservationIgnored private var detector = TurnDetector()
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// The turn being transcribed, between the end of your words and the message.
    @ObservationIgnored private var hearing: Task<Void, Never>?
    @ObservationIgnored private var turn: TranscriptionStream?
    @ObservationIgnored private let lease = "usualbot:call:\(UUID().uuidString)"
    @ObservationIgnored private let started = Date()

    // The reply being spoken.
    @ObservationIgnored private var replyStart: Int?
    @ObservationIgnored private var reply = SpokenReply()
    @ObservationIgnored private var speech: SpeechStream?
    @ObservationIgnored private var playing: Task<Void, Never>?
    /// The reply's sentences, kept for `/api/audio/speak` if the stream can't say them.
    @ObservationIgnored private var sentences: [String] = []
    @ObservationIgnored private var sentDone = false
    @ObservationIgnored private var speechOver = false

    init(thread: ChatThread, profile: String, transcriber: GatewayTranscriber, speaker: GatewaySpeaker) {
        self.thread = thread
        self.profile = profile
        self.transcriber = transcriber
        self.speaker = speaker
    }

    func start() async {
        guard phase == .starting else { return }
        if let problem = await Dictation.permissionProblem(speech: false) {
            phase = .failed(problem)
            return
        }
        guard phase == .starting else { return }
        do {
            let audio = try CallAudio.start()
            self.audio = audio
            Self.log.notice(
                "Gateway call started, echo cancellation \(audio.cancelsEcho ? "on" : "off", privacy: .public)")
        } catch let error as CallAudio.Problem {
            phase = .failed(error.message)
            return
        } catch {
            phase = .failed(String(localized: "The microphone couldn't start: \(error.localizedDescription)"))
            return
        }
        let tap = tap
        audio?.listen(pcm: { tap.add($0) })
        transcriber.warmUp(lease, active: true, profile: profile)
        speaker.warmUp(lease, active: true, profile: profile)
        phase = .listening
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func end() {
        guard phase != .ended else { return }
        phase = .ended
        stop()
    }

    private func fail(_ message: String) {
        Self.log.error("Gateway call failed: \(message, privacy: .public)")
        phase = .failed(message)
        stop()
    }

    private func stop() {
        loop?.cancel()
        hearing?.cancel()
        turn?.cancel()
        stopSpeech()
        audio?.shutdown()
        audio = nil
        tap.end()
        transcriber.warmUp(lease, active: false, profile: profile)
        speaker.warmUp(lease, active: false, profile: profile)
    }

    // MARK: The loop

    /// Twenty times a second: your loudness for turns, and the reply's new sentences.
    private func tick() {
        let level = audio?.level ?? 0
        levels = Array(levels.dropFirst()) + [phase == .listening && !muted ? level : 0]
        listen(level)
        feedReply()
    }

    private func listen(_ level: Double) {
        guard let audio else { return }
        let now = Date().timeIntervalSince(started)
        switch phase {
        case .listening where hearing == nil:
            switch detector.heard(level, at: now) {
            case .started: beginTurn()
            case .ended: endTurn()
            case nil: break
            }
        case .thinking, .speaking:
            // Without echo cancellation the microphone hears the Bot: take turns instead.
            guard audio.cancelsEcho, hearing == nil else { return }
            if detector.heard(level, at: now) == .started { interrupt() }
        default: break
        }
    }

    // MARK: Your turn

    private func beginTurn() {
        let turn = transcriber.stream(profile: profile) { [weak self] words in
            guard let self, phase == .listening else { return }
            heard = words
            detector.heardWords(at: Date().timeIntervalSince(started))
        }
        self.turn = turn
        tap.begin(turn)
    }

    /// You stopped talking: the gateway's words for it become the next message.
    private func endTurn() {
        let audio = tap.end()
        guard let turn else { return }
        self.turn = nil
        phase = .thinking
        hearing = Task { [weak self] in
            let words: String
            do {
                words = try await Self.words(turn, audio: audio, transcriber: self?.transcriber, profile: self?.profile)
            } catch {
                self?.hearing = nil
                guard !Task.isCancelled else { return }
                self?.fail(GatewayTranscriber.problem(for: error, use: .call))
                return
            }
            guard let self, !Task.isCancelled else { return }
            await send(words)
            // Until it's sent, nothing you say cuts in: there's no reply to cut off yet.
            hearing = nil
        }
    }

    /// The stream's final words, or else the turn uploaded.
    private static func words(
        _ turn: TranscriptionStream, audio: Data, transcriber: GatewayTranscriber?, profile: String?
    ) async throws -> String {
        if let words = await turn.finish() { return words }
        // Under 0.3 s is a noise, not words.
        guard audio.count >= 16_000 * 2 * 3 / 10, let transcriber else { return "" }
        return try await transcriber.transcribe(TurnTap.wav(audio), mimeType: "audio/wav", profile: profile)
    }

    private func send(_ words: String) async {
        heard = ""
        detector.reset()
        guard !words.isEmpty else {
            phase = .listening
            return
        }
        // A reply you cut off is still stopping; sending now would steer it instead.
        for _ in 0..<30 where thread.state.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard phase == .thinking else { return }
        guard thread.canSend else {
            fail(String(localized: "The chat isn't connected, so the call can't go on. Try again when it's back."))
            return
        }
        transcript.append(VoiceCall.Line(fromYou: true, text: words))
        thread.send(words)
        replyStart = thread.state.items.count
        detector.startAfter = TurnDetector.bargeInAfter
        reply = SpokenReply()
        sentences = []
        sentDone = false
        speechOver = false
    }

    // MARK: The reply

    private func feedReply() {
        guard let replyStart, phase == .thinking || phase == .speaking else { return }
        let done = !thread.state.isRunning
        let new = reply.sentences(in: replyText(from: replyStart), final: done)
        if !new.isEmpty {
            let speech = speech ?? openSpeech()
            for sentence in new {
                sentences.append(sentence)
                speech.say(sentence)
                // One line per reply: the first sentence starts it.
                if sentences.count > 1, let last = transcript.last, !last.fromYou {
                    transcript[transcript.count - 1].text += " " + sentence
                } else {
                    transcript.append(VoiceCall.Line(fromYou: false, text: sentence))
                }
            }
        }
        guard done else { return }
        if !sentDone {
            sentDone = true
            speech?.done()
            if speech == nil { speechOver = true }
        }
        if speechOver, audio?.isSpeaking != true { replyFinished() }
    }

    private func openSpeech() -> SpeechStream {
        let speech = speaker.stream(profile: profile)
        self.speech = speech
        playing = Task { [weak self] in
            var rate = 24_000.0
            // Until the reply is heard to be a voice, its audio waits here to be checked.
            var held = Data()
            var checked = false
            for await event in speech.events {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .start(let sampleRate):
                    rate = sampleRate
                    held = Data()
                    checked = false
                case .pcm(let pcm) where checked:
                    play(pcm, rate: rate)
                case .pcm(let pcm):
                    held += pcm
                    // A fifth of a second is enough to tell.
                    guard held.count >= Int(rate / 5) * 2 else { continue }
                    guard let voice = check(held) else { return }
                    play(held, rate: rate)
                    held = Data()
                    checked = voice
                case .end:
                    guard !held.isEmpty else { break }
                    guard check(held) != nil else { return }
                    play(held, rate: rate)
                    held = Data()
                case .fallback:
                    await speakClips()
                    return
                }
            }
            self?.speechOver = true
        }
        return speech
    }

    private func play(_ pcm: Data, rate: Double) {
        if phase == .thinking { phase = .speaking }
        audio?.play(pcm16: pcm, sampleRate: rate)
    }

    /// `true` if the audio is a voice, `false` if too quiet to tell, and `nil`, with the call
    /// stopped, if it's noise: garbled audio is never played loud into someone's ear.
    private func check(_ pcm: Data) -> Bool? {
        switch PCMCheck.judge(pcm16: pcm) {
        case .speech: return true
        case .quiet: return false
        case .noise:
            fail(
                String(
                    localized:
                        "The gateway's voice came back as noise, so the call stopped it. Try again, or use On-device."))
            return nil
        }
    }

    /// The stream couldn't speak: each sentence as a clip instead, waiting for the ones still
    /// being written.
    private func speakClips() async {
        var next = 0
        while !Task.isCancelled {
            if next < sentences.count {
                let sentence = sentences[next]
                next += 1
                do {
                    let clip = try await speaker.speak(sentence, profile: profile)
                    guard !Task.isCancelled else { return }
                    if phase == .thinking { phase = .speaking }
                    guard audio?.play(clip: clip.audio, fileExtension: clip.fileExtension) == true else {
                        fail(String(localized: "The gateway's voice came back in a format this device can't play."))
                        return
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    fail(GatewaySpeaker.problem(for: error))
                    return
                }
            } else if sentDone {
                speechOver = true
                return
            } else {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func replyFinished() {
        stopSpeech()
        replyStart = nil
        detector.reset()
        detector.startAfter = TurnDetector.listenAfter
        phase = .listening
    }

    private func stopSpeech() {
        playing?.cancel()
        playing = nil
        speech?.stop()
        speech = nil
        audio?.stopSpeaking()
    }

    /// You spoke over the Bot: stop its voice and its turn, and hear you out.
    private func interrupt() {
        stopSpeech()
        replyStart = nil
        if thread.state.isRunning { thread.stop() }
        detector.startAfter = TurnDetector.listenAfter
        phase = .listening
        // The detector already counts you as talking; what you said so far is in the pre-roll.
        beginTurn()
    }

    private func replyText(from start: Int) -> String {
        let items = thread.state.items
        var parts: [String] = []
        if start < items.count {
            for item in items[start...] {
                if case .assistant(let text) = item.content { parts.append(text) }
            }
        }
        if !thread.state.draft.isEmpty { parts.append(thread.state.draft) }
        return parts.joined(separator: "\n\n")
    }

    private static let log = Logger(subsystem: "UsualBot", category: "call")
}

/// The microphone's PCM on its way to a turn: the last moment before you started is kept, so a
/// turn begins with your first word, not after it. Fed on the audio thread.
final class TurnTap: Sendable {
    private struct State {
        var preroll = Data()
        var turn: TranscriptionStream?
        var recorded = Data()
    }

    /// Half a second of 16 kHz 16-bit audio.
    private static let prerollBytes = 16_000
    private let state = OSAllocatedUnfairLock(initialState: State())

    func add(_ pcm: Data) {
        let turn = state.withLock { state -> TranscriptionStream? in
            if state.turn != nil {
                state.recorded.append(pcm)
            } else {
                state.preroll.append(pcm)
                if state.preroll.count > Self.prerollBytes {
                    state.preroll.removeFirst(state.preroll.count - Self.prerollBytes)
                }
            }
            return state.turn
        }
        turn?.push(pcm)
    }

    /// Starts sending to `turn`, with what came just before.
    func begin(_ turn: TranscriptionStream) {
        let preroll = state.withLock { state -> Data in
            state.turn = turn
            state.recorded = state.preroll
            state.preroll = Data()
            return state.recorded
        }
        turn.push(preroll)
    }

    /// Stops sending, and gives the turn's audio.
    @discardableResult
    func end() -> Data {
        state.withLock { state in
            state.turn = nil
            defer { state.recorded = Data() }
            return state.recorded
        }
    }

    /// 16 kHz mono 16-bit PCM in a WAV file, for uploading a turn.
    static func wav(_ pcm: Data) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var data = Data("RIFF".utf8)
        data += le(UInt32(36 + pcm.count))
        data += Data("WAVEfmt ".utf8)
        data += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1)) + le(UInt32(16_000)) + le(UInt32(32_000))
        data += le(UInt16(2)) + le(UInt16(16))
        data += Data("data".utf8) + le(UInt32(pcm.count))
        return data + pcm
    }
}
