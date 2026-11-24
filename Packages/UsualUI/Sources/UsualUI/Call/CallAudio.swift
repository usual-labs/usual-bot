import AVFoundation
import Speech
import os

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
    /// Where the microphone goes as 16 kHz 16-bit PCM, for the gateway; `nil` while nothing takes it.
    private var pcmSink: (@Sendable (Data) -> Void)?
    private var pcmConverter: AVAudioConverter?
    private let pcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var muted = false
    private var pending = 0
    private var latestLevel = 0.0
    /// Bumps when playback is cut short, so callbacks of dropped buffers count for nothing.
    private var generation = 0
    private var watch = MicWatch(at: CallAudio.now)
    private var observers: [NSObjectProtocol] = []

    /// Whether the system's echo cancellation is on, so you can speak over the agent.
    let cancelsEcho: Bool

    /// With `cancellingEcho`, what the speakers play is taken out of what the microphone hears.
    /// It can fail to start on a Mac (error -10875, depending on the audio devices); the caller
    /// then tries again without it.
    init(cancellingEcho: Bool) throws {
        try Self.activateSession(cancellingEcho: cancellingEcho)
        let input = engine.inputNode
        if cancellingEcho { try input.setVoiceProcessingEnabled(true) }
        cancelsEcho = cancellingEcho
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: voiceFormat)
        try startEngine()
        observeStops()
    }

    private static func activateSession(cancellingEcho: Bool) throws {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: cancellingEcho ? .voiceChat : .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        #endif
    }

    /// Taps the microphone in its current format and starts the engine.
    private func startEngine() throws {
        let input = engine.inputNode
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

    // MARK: Staying on

    /// For the log only: what stopped the engine. The watch restarts it whatever the reason.
    private func observeStops() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
                Self.log.notice("Call audio configuration changed")
            })
        #if os(iOS)
            observers.append(
                center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
                    let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    let reason = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
                    Self.log.notice(
                        "Call audio interrupted: type \(type ?? 99), reason \(reason ?? 99)")
                })
            observers.append(
                center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
                    let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    Self.log.notice("Call audio route changed: reason \(reason ?? 99)")
                })
        #endif
    }

    /// Starts the microphone again if it stopped. `false` once that keeps failing and the call
    /// should end. Called on the call's loop, a few times a second.
    func keepListening() -> Bool {
        let running = engine.isRunning
        let action = lock.withLock { watch.check(running: running, at: Self.now) }
        switch action {
        case .fine:
            return true
        case .giveUp:
            Self.log.error("Call audio stopped and couldn't start again")
            return false
        case .restart:
            Self.log.notice(
                "Call audio stopped (engine \(running ? "running" : "stopped", privacy: .public)); starting it again")
            do {
                try restart()
            } catch {
                Self.log.error("Call audio didn't start again: \(error.localizedDescription, privacy: .public)")
            }
            return true
        }
    }

    private func restart() throws {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        // The player stopped with the engine, and its queued buffers won't finish.
        lock.withLock {
            generation += 1
            pending = 0
        }
        player.stop()
        try Self.activateSession(cancellingEcho: cancelsEcho)
        try startEngine()
    }

    /// Why a call ended when `keepListening()` gave up.
    static var stopped: String {
        String(
            localized:
                "The microphone stopped and couldn't start again. If a phone call or another app is using it, end that and call again."
        )
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private static let log = Logger(subsystem: "UsualBot", category: "call")

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

    /// Where the microphone's audio goes as 16 kHz mono 16-bit PCM; `nil` stops it.
    func listen(pcm sink: (@Sendable (Data) -> Void)?) {
        lock.withLock { pcmSink = sink }
    }

    func setMuted(_ muted: Bool) {
        lock.withLock { self.muted = muted }
    }

    /// The microphone's loudness, 0…1.
    var level: Double { lock.withLock { latestLevel } }

    private func heard(_ buffer: AVAudioPCMBuffer) {
        let level = Self.level(of: buffer)
        let (request, sink) = lock.withLock {
            () -> (SFSpeechAudioBufferRecognitionRequest?, (@Sendable (Data) -> Void)?) in
            latestLevel = muted ? 0 : level
            watch.heardBuffer(at: Self.now)
            return muted ? (nil, nil) : (self.request, pcmSink)
        }
        request?.append(buffer)
        guard let sink else { return }
        // Only the tap's thread touches the converter.
        if pcmConverter?.inputFormat != buffer.format {
            pcmConverter = AVAudioConverter(from: buffer.format, to: pcmFormat)
        }
        guard let pcmConverter, let converted = GatewayRecording.convert(buffer, with: pcmConverter, to: pcmFormat)
        else { return }
        sink(GatewayRecording.pcm16(converted))
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

    /// Queues the gateway's voice: 16-bit little-endian mono PCM at `sampleRate`.
    func play(pcm16 data: Data, sampleRate: Double) {
        let frames = AVAudioFrameCount(data.count / 2)
        guard frames > 0,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let samples = buffer.int16ChannelData?[0]
        else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { bytes in
            for index in 0..<Int(frames) {
                samples[index] = Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
            }
        }
        play(buffer)
    }

    /// Queues a whole clip of the gateway's voice, in any format AVFoundation reads. `false` if it
    /// can't be read.
    func play(clip audio: Data, fileExtension: String) -> Bool {
        let url = FileManager.default.temporaryDirectory.appending(path: "call-\(UUID().uuidString).\(fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? audio.write(to: url)) != nil, let file = try? AVAudioFile(forReading: url),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            (try? file.read(into: buffer)) != nil, buffer.frameLength > 0
        else { return false }
        play(buffer)
        return true
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
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        stopSpeaking()
        listen(into: nil)
        listen(pcm: nil)
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
