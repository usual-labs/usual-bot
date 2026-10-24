import AVFoundation
import Speech

/// A call's audio: one engine for the microphone and the agent's voice, so the system's echo
/// cancellation keeps the agent from hearing itself. Lives off the main actor: the microphone
/// tap and playback callbacks run on audio threads.
final class CallAudio: @unchecked Sendable {
    struct Problem: Error {
        let message: String
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// What the agent's voice plays in; synthesizer buffers are converted to it.
    private let voiceFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var muted = false
    private var pending = 0
    private var latestLevel = 0.0
    /// Bumps when playback is cut short, so callbacks of dropped buffers count for nothing.
    private var generation = 0

    /// Whether the system's echo cancellation is on, so you can speak over the agent.
    let cancelsEcho: Bool

    /// With `cancellingEcho`, what the speakers play is taken out of what the microphone hears.
    /// It can fail to start on a Mac (error -10875, depending on the audio devices); the caller
    /// then tries again without it.
    init(cancellingEcho: Bool) throws {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: cancellingEcho ? .voiceChat : .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        #endif
        let input = engine.inputNode
        if cancellingEcho { try input.setVoiceProcessingEnabled(true) }
        cancelsEcho = cancellingEcho
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: voiceFormat)
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw Problem(message: String(localized: "No microphone is connected."))
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.heard(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// Echo cancellation when it starts, otherwise without.
    static func start() throws -> CallAudio {
        do {
            return try CallAudio(cancellingEcho: true)
        } catch {
            return try CallAudio(cancellingEcho: false)
        }
    }

    // MARK: Listening

    /// Where the microphone's audio goes; `nil` while nothing listens.
    func listen(into request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock { self.request = request }
    }

    func setMuted(_ muted: Bool) {
        lock.withLock { self.muted = muted }
    }

    /// The microphone's loudness, 0…1.
    var level: Double { lock.withLock { latestLevel } }

    private func heard(_ buffer: AVAudioPCMBuffer) {
        let level = Self.level(of: buffer)
        let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
            latestLevel = muted ? 0 : level
            return muted ? nil : self.request
        }
        request?.append(buffer)
    }

    // MARK: Speaking

    /// Buffers of the agent's voice still to play.
    var isSpeaking: Bool { lock.withLock { pending > 0 } }

    /// Queues a piece of the agent's voice.
    func play(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        let generation = lock.withLock { () -> Int in
            pending += 1
            return self.generation
        }
        player.scheduleBuffer(converted, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.lock.withLock { if self?.generation == generation { self?.pending -= 1 } }
        }
        if !player.isPlaying { player.play() }
    }

    /// Cuts the agent off: drops everything queued.
    func stopSpeaking() {
        lock.withLock {
            generation += 1
            pending = 0
        }
        player.stop()
    }

    func shutdown() {
        stopSpeaking()
        listen(into: nil)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == voiceFormat { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: voiceFormat) else { return nil }
        let ratio = voiceFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: voiceFormat, frameCapacity: capacity) else { return nil }
        // The input block runs inside `convert`, on this thread, before it returns.
        nonisolated(unsafe) var supplied = false
        nonisolated(unsafe) let input = buffer
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        return error == nil && output.frameLength > 0 ? output : nil
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
