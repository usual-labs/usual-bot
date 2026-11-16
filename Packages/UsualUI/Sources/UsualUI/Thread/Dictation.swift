import AVFoundation
import HermesKit
import Observation
import Speech
import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Speech to text for the message box. On-device, with Apple's recognizer (on the device when it
/// can be, so audio stays local and it works offline), words appear as you speak and stop when you
/// tap the button again, send, or the recognizer ends (about a minute). Through the gateway
/// (`DictationSettings`, `DictationGateway.swift`), the Bot's own speech-to-text hears you: live
/// words where the gateway streams them, otherwise all at once after you stop.
@MainActor
@Observable
final class Dictation {
    enum State: Equatable {
        case idle
        case starting
        case listening
        /// The recording is with the gateway, or with On-device after the gateway failed.
        case transcribing
        /// Microphone or speech recognition is off for the app; the message says where to turn it on.
        case denied(String)
        case failed(String)
    }

    // Set here and in DictationGateway.swift; views only read them.
    var state = State.idle
    /// How loud the microphone is, 0…1, for the button's ring.
    var level: Double = 0
    /// The recording is going to the gateway: sending waits for its words.
    var throughGateway = false
    /// The gateway couldn't transcribe the recording, which is kept for On-device to try.
    var canUseOnDevice = false
    /// Seconds before gateway dictation stops by itself, in its last 15.
    var secondsLeft: Double?

    @ObservationIgnored private var session: SpeechSession?
    /// What the message box held when listening started; speech goes after it.
    @ObservationIgnored var prefix = ""
    /// Words arrived in this recording, so an error ends dictation rather than preventing it.
    @ObservationIgnored var heardWords = false
    /// The gateway recording in progress, and what it delivers to (`DictationGateway.swift`).
    @ObservationIgnored var gateway: GatewayJob?

    var isListening: Bool { state == .listening || state == .starting }
    /// Listening or transcribing: the button belongs to dictation.
    var isActive: Bool { isListening || state == .transcribing }
    /// Gateway words are still to come, so the box mustn't send yet.
    var holdsSending: Bool { throughGateway && isActive }

    /// Starts listening. `update` gets the box's whole new text each time the words change, and
    /// `current` reads it. With a `transcriber` the gateway hears you, as `profile`'s Bot.
    func start(
        after text: String, transcriber: GatewayTranscriber? = nil, profile: String? = nil,
        current: @escaping @MainActor () -> String = { "" }, update: @escaping @MainActor (String) -> Void
    ) {
        guard !isActive else { return }
        discardKeptRecording()
        prefix = text
        heardWords = false
        state = .starting
        if let transcriber {
            startGateway(transcriber, profile: profile, current: current, update: update)
            return
        }
        throughGateway = false
        var spoken = Utterances()
        Task {
            if let problem = await Self.permissionProblem() {
                state = .denied(problem)
                return
            }
            guard state == .starting else { return }  // Stopped while asking.
            do {
                let session = try SpeechSession(
                    onText: { [weak self] words, endsUtterance in
                        guard let self else { return }
                        self.heardWords = true
                        update(Self.merge(self.prefix, spoken.adding(words, endsUtterance: endsUtterance)))
                    },
                    onLevel: { [weak self] level in self?.level = level },
                    onEnd: { [weak self] error in self?.finish(error) })
                self.session = session
                state = .listening
            } catch {
                state = .failed(Self.describe(error))
            }
        }
    }

    /// Stops listening. On-device keeps the words so far; the gateway now transcribes the recording.
    func stop() {
        if throughGateway {
            if isListening { finishGateway() }
            return
        }
        session?.stop()
        session = nil
        level = 0
        if isListening { state = .idle }
    }

    /// The box moves to another conversation or goes. Words still to come from the gateway land
    /// in the draft they were for (`update` writes to it); a problem with them is then lost.
    func leave() {
        guard throughGateway else { return stop() }
        if canUseOnDevice {
            discardKeptRecording()
        } else {
            if isListening { finishGateway() }
            gateway?.detached = true
            gateway = nil
        }
        level = 0
        secondsLeft = nil
        state = .idle
    }

    /// Clears a denied or failed message.
    func dismissProblem() {
        guard !isActive else { return }
        discardKeptRecording()
        state = .idle
    }

    private func finish(_ error: (any Error)?) {
        session = nil
        level = 0
        // Cancelling, or hearing nothing, isn't worth a message.
        if let error, state == .listening, !Self.isQuietEnd(error) {
            state = .failed(
                heardWords
                    ? Self.describe(error)
                    : String(
                        localized:
                            "Dictation couldn't start: speech recognition isn't available on this device right now."))
        } else if isListening {
            state = .idle
        }
    }

    /// The box's text with what was said after it.
    nonisolated static func merge(_ prefix: String, _ words: String) -> String {
        guard !words.isEmpty else { return prefix }
        guard !prefix.isEmpty else { return words }
        return prefix.last?.isWhitespace == true ? prefix + words : prefix + " " + words
    }

    // MARK: Permissions

    /// Asks for the microphone, and for speech recognition where Apple's recognizer runs, the first
    /// time; afterwards says what's off.
    static func permissionProblem(speech: Bool = true) async -> String? {
        if speech {
            // `@Sendable`: the answer comes on a background queue, and a closure made here would
            // otherwise be main-actor isolated and stop the app when it runs there.
            let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
            }
            guard status == .authorized else {
                return String(localized: "Speech recognition is off for Usual Bot. Turn it on in Settings › Privacy.")
            }
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            return String(localized: "The microphone is off for Usual Bot. Turn it on in Settings › Privacy.")
        }
        return nil
    }

    /// Opens the privacy settings where dictation's permissions live.
    static func openSettings() {
        #if canImport(AppKit)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        #else
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }

    nonisolated static func isQuietEnd(_ error: any Error) -> Bool {
        let error = error as NSError
        // 216: cancelled; 1110: no speech heard; 301: request ended.
        return error.domain == "kAFAssistantErrorDomain" && [216, 301, 1110].contains(error.code)
    }

    nonisolated static func describe(_ error: any Error) -> String {
        if let error = error as? SpeechSession.Problem { return error.message }
        if let error = error as? GatewayRecording.Problem { return error.message }
        return String(localized: "Dictation stopped: \(error.localizedDescription)")
    }
}

/// Everything said in one recording. After a pause Apple's recognizer starts a new utterance and
/// its results hold only that, so the finished ones are kept here and the current one goes after.
struct Utterances {
    private var done = ""
    private var current = ""
    private var currentEnded = false

    /// The whole text, given a result's words and whether they close an utterance (the result
    /// carries `speechRecognitionMetadata`).
    mutating func adding(_ words: String, endsUtterance: Bool) -> String {
        guard !words.isEmpty else { return text }
        // The same words again, as the final result repeats the last utterance.
        guard words != current else {
            currentEnded = currentEnded || endsUtterance
            return text
        }
        if currentEnded || Self.startsOver(words, after: current) {
            done = Dictation.merge(done, current)
        }
        current = words
        currentEnded = endsUtterance
        return text
    }

    var text: String { Dictation.merge(done, current) }

    /// Words that don't revise the current utterance but begin a new one, for when the recognizer
    /// doesn't say the last one ended: much shorter, and starting with another word.
    static func startsOver(_ words: String, after current: String) -> Bool {
        guard !current.isEmpty, words.count * 2 < current.count else { return false }
        func first(_ text: String) -> String {
            String(text.split(separator: " ").first ?? "").lowercased().filter(\.isLetter)
        }
        return first(words) != first(current)
    }
}

/// One recording: the microphone feeding the recognizer. Lives off the main actor because the
/// audio tap runs on the audio thread; its callbacks hop back to the main actor.
private final class SpeechSession: @unchecked Sendable {
    struct Problem: Error {
        let message: String
    }

    private let engine = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    init(
        onText: @escaping @MainActor (String, Bool) -> Void, onLevel: @escaping @MainActor (Double) -> Void,
        onEnd: @escaping @MainActor ((any Error)?) -> Void
    ) throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw Problem(message: String(localized: "Dictation isn't available for your language right now."))
        }
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        // On the device when it can: audio stays here and it works offline.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        #if os(iOS)
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw Problem(message: String(localized: "No microphone is connected."))
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [request] buffer, _ in
            request.append(buffer)
            let level = MicLevel.of(buffer)
            Task { @MainActor in onLevel(level) }
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let endsUtterance = result?.speechRecognitionMetadata != nil
            let ended = error != nil || result?.isFinal == true
            Task { @MainActor in
                if let words { onText(words, endsUtterance) }
                if ended { onEnd(error) }
            }
            if ended { self?.stopAudio() }
        }
    }

    func stop() {
        request.endAudio()
        task?.finish()
        stopAudio()
    }

    private func stopAudio() {
        guard engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// The mic in the message box: tap to dictate, tap again to stop. While listening a ring around
/// it follows your voice; in gateway dictation's last 15 seconds a second ring runs down. While
/// the gateway transcribes, tapping cancels.
struct MicButton: View {
    let dictation: Dictation
    /// Gateway dictation is chosen: said in the label, not drawn.
    var throughGateway = false
    let start: () -> Void
    @Environment(\.composerButtonSize) private var size

    var body: some View {
        Button {
            if dictation.state == .transcribing {
                dictation.cancel()
            } else if dictation.isListening {
                dictation.stop()
            } else {
                start()
            }
        } label: {
            ComposerGlyph(systemImage: glyph, scale: dictation.isActive ? 11 : 13)
        }
        .composerGlass()
        .overlay {
            if dictation.isListening {
                Circle()
                    .stroke(Theme.ink.opacity(0.25), lineWidth: 3)
                    .frame(width: size, height: size)
                    .scaleEffect(1 + dictation.level * 0.45)
                    .animation(.easeOut(duration: 0.12), value: dictation.level)
                    .allowsHitTesting(false)
            }
            if let secondsLeft = dictation.secondsLeft {
                Circle()
                    .trim(from: 0, to: secondsLeft / Dictation.countdown)
                    .stroke(Theme.ink.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 6, height: size + 6)
                    .animation(.linear(duration: 0.25), value: secondsLeft)
                    .allowsHitTesting(false)
            }
        }
        .help(label)
        .accessibilityLabel(Text(label))
    }

    private var glyph: String {
        if dictation.state == .transcribing { return "xmark" }
        return dictation.isListening ? "stop.fill" : "mic.fill"
    }

    private var label: String {
        if dictation.state == .transcribing { return String(localized: "Cancel transcription") }
        if dictation.isListening { return String(localized: "Stop dictation") }
        return throughGateway ? String(localized: "Dictate through your gateway") : String(localized: "Dictate")
    }
}

/// Why dictation can't run, under the message box, with a way to fix it.
struct DictationProblem: View {
    let message: String
    let showsSettings: Bool
    /// The gateway failed with a recording On-device can transcribe.
    var useOnDevice: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .scaledFont(size: 12.5)
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsSettings {
                Button("Open Settings", action: Dictation.openSettings)
                    .buttonStyle(.clickable(.bordered))
                    .controlSize(.small)
            }
            if let useOnDevice {
                Button("Use On-device", action: useOnDevice)
                    .buttonStyle(.clickable(.bordered))
                    .controlSize(.small)
                    .accessibilityHint(Text("Transcribes this recording on this device"))
            }
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.clickable(.borderless))
                .foregroundStyle(Theme.secondaryInk)
        }
        .padding(.horizontal, 8)
    }
}

/// Under the message box while a recording turns into words.
struct DictationTranscribing: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text("Transcribing…")
                .scaledFont(size: 12.5)
                .foregroundStyle(Theme.secondaryInk)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Starts a voice call, beside the mic in an empty message box.
struct CallStartButton: View {
    let action: () -> Void

    var body: some View {
        // In the spot Send takes, so in the same colour.
        Button(action: action) {
            ComposerGlyph(systemImage: "waveform", prominent: true)
        }
        .composerGlass(prominent: true)
        .help("Voice call")
        .accessibilityLabel(Text("Start a voice call"))
    }
}
