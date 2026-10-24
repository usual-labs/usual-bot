import AVFoundation
import Observation
import Speech
import SwiftUI

#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Speech to text for the message box, with Apple's recognizer: on the device when it can be,
/// so audio stays local and it works offline. Words appear as you speak and stop when you tap
/// the button again, send, or the recognizer ends (about a minute).
@MainActor
@Observable
final class Dictation {
    enum State: Equatable {
        case idle
        case starting
        case listening
        /// Microphone or speech recognition is off for the app; the message says where to turn it on.
        case denied(String)
        case failed(String)
    }

    private(set) var state = State.idle
    /// How loud the microphone is, 0…1, for the button's ring.
    private(set) var level: Double = 0

    @ObservationIgnored private var session: SpeechSession?
    /// What the message box held when listening started; speech goes after it.
    @ObservationIgnored private var prefix = ""
    /// Words arrived in this recording, so an error ends dictation rather than preventing it.
    @ObservationIgnored private var heardWords = false

    var isListening: Bool { state == .listening || state == .starting }

    /// Starts listening. `update` gets the box's whole new text each time the words change.
    func start(after text: String, update: @escaping @MainActor (String) -> Void) {
        guard !isListening else { return }
        prefix = text
        heardWords = false
        state = .starting
        Task {
            if let problem = await Self.permissionProblem() {
                state = .denied(problem)
                return
            }
            guard state == .starting else { return }  // Stopped while asking.
            do {
                let session = try SpeechSession(
                    onText: { [weak self] words in
                        guard let self else { return }
                        self.heardWords = true
                        update(Self.merge(self.prefix, words))
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

    /// Stops listening and keeps the words so far.
    func stop() {
        session?.stop()
        session = nil
        level = 0
        if isListening { state = .idle }
    }

    /// Clears a denied or failed message.
    func dismissProblem() {
        if !isListening { state = .idle }
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

    /// Asks for the microphone and speech recognition the first time; afterwards says what's off.
    static func permissionProblem() async -> String? {
        // `@Sendable`: the answer comes on a background queue, and a closure made here would
        // otherwise be main-actor isolated and stop the app when it runs there.
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
        guard speech == .authorized else {
            return String(localized: "Speech recognition is off for Usual Bot. Turn it on in Settings › Privacy.")
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

    private nonisolated static func isQuietEnd(_ error: any Error) -> Bool {
        let error = error as NSError
        // 216: cancelled; 1110: no speech heard; 301: request ended.
        return error.domain == "kAFAssistantErrorDomain" && [216, 301, 1110].contains(error.code)
    }

    private nonisolated static func describe(_ error: any Error) -> String {
        if let error = error as? SpeechSession.Problem { return error.message }
        return String(localized: "Dictation stopped: \(error.localizedDescription)")
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
        onText: @escaping @MainActor (String) -> Void, onLevel: @escaping @MainActor (Double) -> Void,
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
            let level = Self.level(of: buffer)
            Task { @MainActor in onLevel(level) }
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let ended = error != nil || result?.isFinal == true
            Task { @MainActor in
                if let words { onText(words) }
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

    /// Loudness of one buffer, 0…1, from its RMS in decibels (−50 dB is silence).
    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let decibels = 20 * log10(max(sqrt(sum / Float(count)), 0.000_01))
        return Double(min(max((decibels + 50) / 50, 0), 1))
    }
}

/// The mic in the message box: tap to dictate, tap again to stop. While listening a ring around
/// it follows your voice.
struct MicButton: View {
    let dictation: Dictation
    let start: () -> Void

    var body: some View {
        Button {
            if dictation.isListening { dictation.stop() } else { start() }
        } label: {
            Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: dictation.isListening ? 11 : 13, weight: .semibold))
                .foregroundStyle(dictation.isListening ? Theme.primaryInk : Theme.ink)
                .frame(width: 28, height: 28)
                .background(dictation.isListening ? Theme.primary : Theme.selection, in: Circle())
                .overlay {
                    if dictation.isListening {
                        Circle()
                            .stroke(Theme.ink.opacity(0.25), lineWidth: 3)
                            .scaleEffect(1 + dictation.level * 0.45)
                            .animation(.easeOut(duration: 0.12), value: dictation.level)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(dictation.isListening ? "Stop dictation" : "Dictate")
        .accessibilityLabel(Text(dictation.isListening ? "Stop dictation" : "Dictate"))
    }
}

/// Why dictation can't run, under the message box, with a way to fix it.
struct DictationProblem: View {
    let message: String
    let showsSettings: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsSettings {
                Button("Open Settings", action: Dictation.openSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, 8)
    }
}

/// Starts a voice call, beside the mic in an empty message box.
struct CallStartButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(Theme.selection, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Voice call")
        .accessibilityLabel(Text("Start a voice call"))
    }
}
