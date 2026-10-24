import AVFoundation
import HermesKit
import Observation
import Speech
import os

/// A spoken conversation with one agent, over its ordinary chat: what you say is sent as a
/// message when you pause, and the reply is read aloud as it streams. Speak while it talks to
/// cut it off. The turns stay in the chat.
@MainActor
@Observable
final class VoiceCall {
    enum Phase: Equatable {
        case starting
        case listening
        /// Your words are sent; the reply hasn't started.
        case thinking
        case speaking
        case ended
        case failed(String)
    }

    /// One side's words in the call's transcript.
    struct Line: Identifiable, Equatable {
        let id = UUID()
        let fromYou: Bool
        var text: String
    }

    private(set) var phase = Phase.starting
    /// What was said in this call, oldest first.
    private(set) var transcript: [Line] = []
    /// The last couple of seconds of loudness, for the bar's dots.
    private(set) var levels = [Double](repeating: 0, count: 14)
    /// Without echo cancellation the call takes turns: it doesn't listen while the agent speaks.
    private(set) var cancelsEcho = true
    /// What you're saying, as it's recognised.
    private(set) var heard = ""
    /// The sentence the agent is saying.
    private(set) var saying = ""
    /// How loud you are, 0…1.
    private(set) var level = 0.0
    var muted = false {
        didSet { audio?.setMuted(muted) }
    }

    let thread: ChatThread
    private var audio: CallAudio?
    private var recognizer = SFSpeechRecognizer(locale: CallSettings.language)
    private var recognition: SFSpeechRecognitionTask?
    /// Which recognition is current; callbacks from earlier ones are ignored.
    private var listenToken = 0
    private var pause: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()
    private var reply = SpokenReply()
    /// Sentences waiting to be spoken.
    private var queue: [String] = []
    private var synthesizing = false
    /// Bumps when the agent is cut off, so its leftover audio is dropped.
    private var speechToken = 0
    /// Where the reply to your last words starts in the transcript.
    private var replyStart: Int?

    /// How long a pause ends what you're saying.
    private static let pauseLength: Duration = .milliseconds(1100)

    init(thread: ChatThread) {
        self.thread = thread
    }

    func start() async {
        guard phase == .starting else { return }
        if let problem = await Dictation.permissionProblem() {
            phase = .failed(problem)
            return
        }
        guard phase == .starting else { return }
        guard recognizer?.isAvailable == true else {
            phase = .failed(String(localized: "Speech recognition isn't available on this device right now."))
            return
        }
        do {
            let audio = try CallAudio.start()
            self.audio = audio
            cancelsEcho = audio.cancelsEcho
            Self.log.notice(
                "Call audio started, echo cancellation \(audio.cancelsEcho ? "on" : "off", privacy: .public)")
        } catch let error as CallAudio.Problem {
            phase = .failed(error.message)
            return
        } catch {
            Self.log.error("Call audio failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(String(localized: "The microphone couldn't start: \(error.localizedDescription)"))
            return
        }
        phase = .listening
        listen()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func end() {
        guard phase != .ended else { return }
        phase = .ended
        loop?.cancel()
        pause?.cancel()
        recognition?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        audio?.shutdown()
        audio = nil
    }

    /// The language changed in the settings: listen in the new one.
    func languageChanged() {
        recognizer = SFSpeechRecognizer(locale: CallSettings.language)
        if phase == .listening { listen() }
    }

    // MARK: Listening

    private func listen() {
        guard let recognizer, let audio else { return }
        recognition?.cancel()
        listenToken += 1
        let token = listenToken
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        audio.listen(into: request)
        // `@Sendable`: the recognizer calls back on its own queue.
        recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let ended = error != nil || result?.isFinal == true
            Task { @MainActor in self?.recognized(words, ended: ended, token: token) }
        }
    }

    private func recognized(_ words: String?, ended: Bool, token: Int) {
        guard token == listenToken, phase != .ended else { return }
        if let words, !words.isEmpty, words != heard {
            // A couple of words while the agent talks is you cutting in, not its own echo.
            if cancelsEcho, phase == .speaking || phase == .thinking, words.split(separator: " ").count >= 2 {
                interrupt()
            }
            heard = words
            pause?.cancel()
            pause = Task { [weak self] in
                try? await Task.sleep(for: Self.pauseLength)
                guard !Task.isCancelled else { return }
                self?.finishSaying()
            }
        }
        // The recognizer stops after silence or about a minute: listen again.
        if ended, pause == nil || heard.isEmpty { listen() }
    }

    /// You paused: send what you said and listen for the next thing.
    private func finishSaying() {
        pause = nil
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = ""
        listen()
        guard !words.isEmpty, thread.canSend else { return }
        transcript.append(Line(fromYou: true, text: words))
        thread.send(words)
        replyStart = thread.state.items.count
        reply = SpokenReply()
        phase = .thinking
    }

    // MARK: Speaking

    /// Ten times a second: picks up new sentences of the reply and notices when it's done.
    private func tick() {
        level = audio?.level ?? 0
        levels = Array(levels.dropFirst()) + [phase == .listening && !muted ? level : 0]
        guard let replyStart, phase == .thinking || phase == .speaking else { return }
        let done = !thread.state.isRunning
        queue += reply.sentences(in: replyText(from: replyStart), final: done)
        speakNext()
        if done, queue.isEmpty, !synthesizing, audio?.isSpeaking != true {
            self.replyStart = nil
            saying = ""
            phase = .listening
            // Taking turns: the agent is done, so listen again from a clean start.
            if !cancelsEcho { listen() }
        }
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

    private func speakNext() {
        guard !synthesizing, !queue.isEmpty, let audio else { return }
        let sentence = queue.removeFirst()
        if phase != .speaking, !cancelsEcho {
            // Taking turns: stop listening so the agent's voice isn't heard as yours.
            listenToken += 1
            recognition?.cancel()
            audio.listen(into: nil)
            heard = ""
        }
        synthesizing = true
        saying = sentence
        if phase == .speaking, let last = transcript.last, !last.fromYou {
            transcript[transcript.count - 1].text += " " + sentence
        } else {
            transcript.append(Line(fromYou: false, text: sentence))
        }
        phase = .speaking
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = CallSettings.voice
        utterance.rate = min(
            AVSpeechUtteranceDefaultSpeechRate * Float(CallSettings.speed), AVSpeechUtteranceMaximumSpeechRate)
        let token = speechToken
        // `@Sendable`: the synthesizer hands buffers over on its own queue. An empty buffer
        // means the sentence is done.
        synthesizer.write(utterance) { @Sendable [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                Task { @MainActor in self?.sentenceWritten(token) }
                return
            }
            audio.play(pcm)
        }
    }

    private func sentenceWritten(_ token: Int) {
        guard token == speechToken else { return }
        synthesizing = false
        speakNext()
    }

    /// You spoke over the agent: stop its voice and its turn, and listen.
    private func interrupt() {
        speechToken += 1
        synthesizer.stopSpeaking(at: .immediate)
        audio?.stopSpeaking()
        queue = []
        synthesizing = false
        saying = ""
        replyStart = nil
        if thread.state.isRunning { thread.stop() }
        phase = .listening
    }

    private static let log = Logger(subsystem: "UsualBot", category: "call")
}
