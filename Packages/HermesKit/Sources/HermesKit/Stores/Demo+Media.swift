#if DEBUG
    import AVFoundation
    import CoreGraphics
    import Foundation

    /// The demo's voice memo and video clip. Nothing is shipped: the first time the demo asks for
    /// one, this device makes it, the voice memo with its own speech synthesizer and the clip
    /// drawn frame by frame here.
    enum DemoMedia {
        static let voiceMemoPath = "/home/hermes/.hermes/profiles/ops/cache/audio/tts_20261102_071502_118204.m4a"
        static let clipPath = "/home/hermes/.hermes/profiles/scribe/cache/video/search-teaser.mp4"

        static let voiceMemoText = """
            Good morning. All three servers are healthy and last night's backups restored cleanly. \
            The only thing to watch is disk space on db-1, which is at 78 percent.
            """

        /// Ops reads its morning summary aloud, as Hermes's `text_to_speech` tool does.
        static var voiceMemoTurn: [HistoryMessage] {
            [
                HistoryMessage(role: "user", text: "Read me the morning summary, I'm driving."),
                HistoryMessage(
                    role: "tool", name: "text_to_speech", context: String(voiceMemoText.prefix(80)),
                    toolCallId: "demo-tts", args: ["text": .string(voiceMemoText)]),
                HistoryMessage(role: "assistant", text: "Here's the summary as a voice memo.\nMEDIA:\(voiceMemoPath)"),
            ]
        }

        /// Scribe's reply in the room with the clip.
        static let clipReply = "Here's the teaser for the post: search finding pages as you type.\nMEDIA:\(clipPath)"

        static var makers: [String: @Sendable () async -> Data?] {
            [voiceMemoPath: { await voiceMemo(voiceMemoText) }, clipPath: { await clip() }]
        }

        /// `text` spoken by the system voice, as AAC in an M4A file.
        @MainActor static func voiceMemo(_ text: String) async -> Data? {
            let url = FileManager.default.temporaryDirectory.appending(path: "UsualBotDemo-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: url) }
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            // Looked up off the main thread: in a simulator without its voices yet, the lookup waits
            // there for good and the app freezes on the chat that holds the memo.
            utterance.voice = await Task.detached { Voice(AVSpeechSynthesisVoice(language: "en-US")) }.value.voice
            let writer = SpeechWriter(url: url)
            let finished = await withCheckedContinuation { continuation in
                writer.onFinish = { continuation.resume(returning: $0) }
                synthesizer.write(utterance) { @Sendable buffer in writer.append(buffer) }
                // Some systems never send the empty buffer that ends speech.
                Task.detached {
                    try? await Task.sleep(for: .seconds(20))
                    writer.finish()
                }
            }
            withExtendedLifetime(synthesizer) {}
            return finished ? try? Data(contentsOf: url) : nil
        }

        private struct Voice: @unchecked Sendable {
            let voice: AVSpeechSynthesisVoice?
            init(_ voice: AVSpeechSynthesisVoice?) { self.voice = voice }
        }

        /// Collects the synthesizer's buffers into a file. Its callbacks come on a queue of its own.
        private final class SpeechWriter: @unchecked Sendable {
            private let url: URL
            private let lock = NSLock()
            private var file: AVAudioFile?
            private var done = false
            var onFinish: ((Bool) -> Void)?

            init(url: URL) { self.url = url }

            func append(_ buffer: AVAudioBuffer) {
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return finish() }
                lock.withLock {
                    guard !done else { return }
                    if file == nil {
                        let settings: [String: Any] = [
                            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: pcm.format.sampleRate,
                            AVNumberOfChannelsKey: pcm.format.channelCount, AVEncoderBitRateKey: 32_000,
                        ]
                        file = try? AVAudioFile(
                            forWriting: url, settings: settings, commonFormat: pcm.format.commonFormat,
                            interleaved: pcm.format.isInterleaved)
                    }
                    try? file?.write(from: pcm)
                }
            }

            func finish() {
                let wrote: Bool? = lock.withLock {
                    guard !done else { return nil }
                    done = true
                    defer { file = nil }  // Closes it.
                    return file != nil
                }
                if let wrote { onFinish?(wrote) }
            }
        }

        /// Four seconds of a search box finding pages, 480 × 270 H.264.
        static func clip() async -> Data? {
            let url = FileManager.default.temporaryDirectory.appending(path: "UsualBotDemo-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: url) }
            let (width, height, fps, frames) = (480, 270, 15, 60)
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 250_000],
                ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                ])
            writer.add(input)
            guard writer.startWriting() else { return nil }
            writer.startSession(atSourceTime: .zero)
            for frame in 0..<frames {
                while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(5)) }
                guard let pool = adaptor.pixelBufferPool else { return nil }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { return nil }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let context = CGContext(
                    data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
                {
                    drawClipFrame(
                        in: context, size: CGSize(width: width, height: height), at: Double(frame) / Double(fps))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                adaptor.append(
                    buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
            }
            input.markAsFinished()
            await writer.finishWriting()
            return writer.status == .completed ? try? Data(contentsOf: url) : nil
        }

        /// A search field fills in, then three results slide up under it.
        private static func drawClipFrame(in context: CGContext, size: CGSize, at time: Double) {
            context.setFillColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            context.fill(CGRect(origin: .zero, size: size))
            // Core Graphics counts up from the bottom.
            let field = CGRect(x: 40, y: size.height - 80, width: size.width - 80, height: 40)
            context.setFillColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            context.addPath(CGPath(roundedRect: field, cornerWidth: 20, cornerHeight: 20, transform: nil))
            context.fillPath()
            let typed = min(1, time / 1.5)
            context.setFillColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1)
            context.fill(CGRect(x: field.minX + 20, y: field.midY - 4, width: (field.width - 60) * typed, height: 8))
            let accent: [(CGFloat, CGFloat, CGFloat)] = [(0.43, 0.48, 1), (0.12, 0.66, 0.44), (0.95, 0.64, 0.06)]
            for (index, color) in accent.enumerated() {
                let shown = min(1, max(0, (time - 1.6 - Double(index) * 0.4) / 0.5))
                guard shown > 0 else { continue }
                let y = field.minY - 50 - CGFloat(index) * 50 - CGFloat(1 - shown) * 20
                context.setAlpha(shown)
                context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
                context.fillEllipse(in: CGRect(x: field.minX + 8, y: y + 8, width: 16, height: 16))
                context.setFillColor(red: 0.7, green: 0.7, blue: 0.74, alpha: 1)
                context.fill(CGRect(x: field.minX + 40, y: y + 18, width: 260 - CGFloat(index) * 40, height: 7))
                context.setFillColor(red: 0.4, green: 0.4, blue: 0.44, alpha: 1)
                context.fill(CGRect(x: field.minX + 40, y: y + 4, width: 200, height: 5))
                context.setAlpha(1)
            }
        }
    }
#endif
