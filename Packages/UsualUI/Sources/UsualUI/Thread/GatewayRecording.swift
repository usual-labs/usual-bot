import AVFoundation

/// The microphone for gateway dictation: a 16 kHz mono AAC file for uploading, and the same
/// audio as 16-bit PCM for the live stream. Lives off the main actor because the audio tap runs
/// on the audio thread.
final class GatewayRecording: @unchecked Sendable {
    // @unchecked: the file is written on the audio thread and closed from the main actor, under `lock`.
    struct Problem: Error {
        let message: String
    }

    static let mimeType = "audio/m4a"

    /// Where the recording is, until whoever finishes with it deletes it.
    let file: URL
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var output: AVAudioFile?
    private var frames = 0

    /// How much has been recorded.
    var seconds: Double { lock.withLock { Double(frames) / 16_000 } }

    init(onPCM: @escaping @Sendable (Data) -> Void, onLevel: @escaping @MainActor (Double) -> Void) throws {
        file = FileManager.default.temporaryDirectory.appending(path: "dictation-\(UUID().uuidString).m4a")
        #if os(iOS)
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0,
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: format, to: target)
        else {
            throw Problem(message: String(localized: "No microphone is connected."))
        }
        output = try AVAudioFile(
            forWriting: file,
            settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1],
            commonFormat: .pcmFormatFloat32, interleaved: false)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            let level = MicLevel.of(buffer)
            Task { @MainActor in onLevel(level) }
            guard let self, let converted = Self.convert(buffer, with: converter, to: target) else { return }
            lock.withLock {
                try? output?.write(from: converted)
                frames += Int(converted.frameLength)
            }
            onPCM(Self.pcm16(converted))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    /// Stops the microphone and finishes the file.
    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            #if os(iOS)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
        lock.withLock {
            output?.close()
            output = nil
        }
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to target: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && converted.frameLength > 0 ? converted : nil
    }

    /// Mono float samples as 16-bit little-endian PCM, which the transcribe stream takes.
    static func pcm16(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let samples = buffer.floatChannelData?[0] else { return Data() }
        var data = Data(capacity: Int(buffer.frameLength) * 2)
        for index in 0..<Int(buffer.frameLength) {
            let value = Int16(max(-1, min(1, samples[index])) * Float(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}

/// How loud the microphone is, for the mic button's ring.
enum MicLevel {
    /// Loudness of one buffer, 0…1, from its RMS in decibels (−50 dB is silence).
    static func of(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let decibels = 20 * log10(max(sqrt(sum / Float(count)), 0.000_01))
        return Double(min(max((decibels + 50) / 50, 0), 1))
    }
}
