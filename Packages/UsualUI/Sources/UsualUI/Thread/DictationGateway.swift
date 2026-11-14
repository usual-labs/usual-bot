import AVFoundation
import HermesKit
import Speech
import SwiftUI

/// Gateway dictation: the microphone is recorded on the device while the Bot's speech-to-text
/// hears it live, if the gateway streams; when you stop, the live words are final, or the
/// recording is uploaded. A failure keeps the recording so On-device can try it. Nothing falls
/// back on its own: you chose where your voice goes.
extension Dictation {
    /// Gateway dictation stops by itself after this long, and transcribes what it has.
    static let limit: Duration = .seconds(600)
    /// The last seconds of `limit`, shown on the button.
    static let countdown: Double = 15

    func startGateway(
        _ transcriber: GatewayTranscriber, profile: String?, current: @escaping @MainActor () -> String,
        update: @escaping @MainActor (String) -> Void
    ) {
        throughGateway = true
        Task { [weak self] in
            let problem = await Self.permissionProblem(speech: false)
            guard let self else { return }
            if let problem {
                state = .denied(problem)
                return
            }
            guard state == .starting else { return }  // Stopped while asking.
            let job = GatewayJob(
                transcriber: transcriber, profile: profile, prefix: prefix, current: current, update: update)
            do {
                try job.begin { [weak self, weak job] level in
                    guard let self, let job, self.gateway === job else { return }
                    self.level = level
                }
            } catch {
                state = .failed(Self.describe(error))
                return
            }
            gateway = job
            state = .listening
            job.limit = Task { [weak self] in await self?.runDown(job) }
        }
    }

    /// Stops the microphone and turns the recording into words.
    func finishGateway() {
        guard let job = gateway else {
            state = .idle
            return
        }
        job.limit?.cancel()
        job.end()
        level = 0
        secondsLeft = nil
        state = .transcribing
        job.work = Task { [weak self] in
            do {
                let words = try await job.transcript()
                job.close()
                if !Task.isCancelled { job.deliver(words) }
                guard let self, self.gateway === job else { return }
                self.gateway = nil
                self.state = .idle
            } catch {
                guard let self, !Task.isCancelled, !job.detached, self.gateway === job else {
                    job.close()
                    return
                }
                job.release()
                self.canUseOnDevice = true
                self.state = .failed(GatewayTranscriber.problem(for: error))
            }
        }
    }

    /// Drops the recording, whether it's being heard or transcribed; the box stays as it was.
    func cancel() {
        guard let job = gateway else { return stop() }
        job.limit?.cancel()
        job.work?.cancel()
        job.end()
        job.close()
        gateway = nil
        level = 0
        secondsLeft = nil
        canUseOnDevice = false
        state = .idle
    }

    /// Transcribes the recording the gateway couldn't, with Apple's recognizer.
    func useOnDevice() {
        guard canUseOnDevice, let job = gateway else { return }
        canUseOnDevice = false
        state = .transcribing
        job.work = Task { [weak self] in
            if let problem = await Self.permissionProblem() {
                job.close()
                guard let self, self.gateway === job else { return }
                self.gateway = nil
                self.state = .denied(problem)
                return
            }
            let outcome: Result<String, any Error>
            do {
                outcome = .success(try await Self.recognize(job.file))
            } catch {
                outcome = .failure(error)
            }
            job.close()
            if case .success(let words) = outcome, !Task.isCancelled { job.deliver(words) }
            guard let self, self.gateway === job else { return }
            self.gateway = nil
            if case .failure(let error) = outcome {
                self.state = .failed(Self.describe(error))
            } else {
                self.state = .idle
            }
        }
    }

    /// Forgets a recording kept for On-device.
    func discardKeptRecording() {
        if canUseOnDevice, let job = gateway {
            job.close()
            gateway = nil
        }
        canUseOnDevice = false
    }

    /// The last seconds before `limit`, then the stop.
    private func runDown(_ job: GatewayJob) async {
        try? await Task.sleep(for: Self.limit - .seconds(Self.countdown))
        guard !Task.isCancelled, gateway === job, state == .listening else { return }
        AccessibilityNotification.Announcement(String(localized: "Dictation stops in 15 seconds")).post()
        let end = ContinuousClock.now + .seconds(Self.countdown)
        while !Task.isCancelled, gateway === job, state == .listening {
            let left = ContinuousClock.now.duration(to: end)
            guard left > .zero else { break }
            secondsLeft = Double(left.components.seconds) + Double(left.components.attoseconds) / 1e18
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !Task.isCancelled, gateway === job, state == .listening else { return }
        finishGateway()
    }

    /// The words in a recording, by Apple's recognizer: on the device when it can be.
    private static func recognize(_ file: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw GatewayRecording.Problem(
                message: String(localized: "Dictation isn't available for your language right now."))
        }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        let answer = RecognitionAnswer()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                answer.start(continuation)
                answer.task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        // Hearing nothing is an empty transcript, not a failure.
                        if Dictation.isQuietEnd(error) {
                            answer.finish(.success(""))
                        } else {
                            answer.finish(.failure(error))
                        }
                    } else if let result, result.isFinal {
                        answer.finish(.success(result.bestTranscription.formattedString))
                    }
                }
            }
        } onCancel: {
            answer.cancel()
        }
    }
}

/// One gateway recording and where its words go. `detached` once the box has moved on: the
/// words still go to the draft they were for, and nothing is shown.
@MainActor
final class GatewayJob {
    let transcriber: GatewayTranscriber
    let profile: String?
    /// Lets the gateway load its local model while you speak (`stt-lease`).
    private let lease = "usualbot:dictation:\(UUID().uuidString)"
    private let prefix: String
    private let current: @MainActor () -> String
    private let update: @MainActor (String) -> Void
    private var stream: TranscriptionStream?
    private var recording: GatewayRecording?
    private(set) var file = URL(filePath: "/dev/null")
    /// Live words came, so the final ones replace them after `prefix`.
    private var sawPartial = false
    private var leased = false
    var detached = false
    var limit: Task<Void, Never>?
    var work: Task<Void, Never>?

    init(
        transcriber: GatewayTranscriber, profile: String?, prefix: String, current: @escaping @MainActor () -> String,
        update: @escaping @MainActor (String) -> Void
    ) {
        self.transcriber = transcriber
        self.profile = profile
        self.prefix = prefix
        self.current = current
        self.update = update
    }

    /// Opens the stream and starts the microphone.
    func begin(onLevel: @escaping @MainActor (Double) -> Void) throws {
        let stream = transcriber.stream(profile: profile) { [weak self] words in
            guard let self, !words.isEmpty else { return }
            sawPartial = true
            update(Dictation.merge(prefix, words))
        }
        do {
            let recording = try GatewayRecording(onPCM: { stream.push($0) }, onLevel: onLevel)
            self.stream = stream
            self.recording = recording
            file = recording.file
        } catch {
            stream.cancel()
            throw error
        }
        transcriber.warmUp(lease, active: true, profile: profile)
        leased = true
    }

    /// Stops the microphone; the file is complete.
    func end() {
        recording?.stop()
    }

    /// The live words if the stream gave them, else the uploaded recording's.
    func transcript() async throws -> String {
        if let words = await stream?.finish() { return words }
        try Task.checkCancellation()
        // Stopped as it started: nothing to hear.
        guard let recording, recording.seconds >= 0.3 else { return "" }
        let audio = try Data(contentsOf: file)
        guard audio.count <= GatewayTranscriber.maxUploadBytes else {
            throw GatewayRecording.Problem(message: String(localized: "That recording is too long for the gateway."))
        }
        return try await transcriber.transcribe(audio, mimeType: GatewayRecording.mimeType, profile: profile)
    }

    /// Puts the words in the box.
    func deliver(_ words: String) {
        if let text = Self.placing(words, prefix: prefix, now: current(), sawPartial: sawPartial) { update(text) }
    }

    /// The box with the final words: in place of the live ones, which followed `prefix`; else
    /// after what's in it `now`, typing since you stopped included. `nil` when nothing was heard.
    nonisolated static func placing(_ words: String, prefix: String, now: String, sawPartial: Bool) -> String? {
        guard !words.isEmpty else { return nil }
        return Dictation.merge(sawPartial ? prefix : now, words)
    }

    /// Lets the gateway's model go.
    func release() {
        guard leased else { return }
        leased = false
        transcriber.warmUp(lease, active: false, profile: profile)
    }

    /// Done with the recording: the stream, the lease and the file go.
    func close() {
        stream?.cancel()
        release()
        try? FileManager.default.removeItem(at: file)
    }
}

/// One answer from a recognition task, which can call back more than once and on any thread.
private final class RecognitionAnswer: @unchecked Sendable {
    // @unchecked: every field is behind `lock`.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, any Error>?
    private var _task: SFSpeechRecognitionTask?
    private var cancelled = false

    var task: SFSpeechRecognitionTask? {
        get { lock.withLock { _task } }
        set {
            let cancel = lock.withLock {
                _task = newValue
                return cancelled
            }
            if cancel { newValue?.cancel() }
        }
    }

    func start(_ continuation: CheckedContinuation<String, any Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func finish(_ result: Result<String, any Error>) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }

    func cancel() {
        let task = lock.withLock {
            cancelled = true
            return _task
        }
        task?.cancel()
        finish(.failure(CancellationError()))
    }
}
