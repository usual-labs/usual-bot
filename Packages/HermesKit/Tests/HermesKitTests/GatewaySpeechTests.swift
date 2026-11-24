import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// The speak stream's far end: records what the app sends and answers from a script.
// @unchecked: the stream's one reader is the only caller of `receive`.
private final class FakeSpeechSocket: SpeechSocket, @unchecked Sendable {
    private let sent = Mutex<[String]>([])
    private let replies: AsyncStream<SpeechFrame>
    private let reply: AsyncStream<SpeechFrame>.Continuation
    /// Called with each text frame the app sends.
    var onSend: ((FakeSpeechSocket, String) -> Void)?

    init() {
        (replies, reply) = AsyncStream<SpeechFrame>.makeStream()
    }

    var frames: [String] { sent.withLock { $0 } }

    func answer(_ frame: SpeechFrame) { reply.yield(frame) }

    func send(text: String) async throws {
        sent.withLock { $0.append(text) }
        onSend?(self, text)
    }

    private lazy var iterator = replies.makeAsyncIterator()

    func receive() async throws -> SpeechFrame {
        guard let frame = await iterator.next() else { throw GatewayError.disconnected }
        return frame
    }

    func close() { reply.finish() }
}

private final class OpenedURLs: Sendable {
    let urls = Mutex<[URL]>([])
}

@MainActor
struct GatewaySpeechTests {
    private func speaker(
        _ http: ScriptedHTTP, socket: (any SpeechSocket)? = nil, opened: OpenedURLs = OpenedURLs()
    ) -> GatewaySpeaker {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        return GatewaySpeaker(
            auth: { auth },
            makeSocket: { url in
                opened.urls.withLock { $0.append(url) }
                guard let socket else { throw GatewayError.unreachable("refused") }
                return socket
            })
    }

    private static let ticket = ScriptedHTTP { request in
        request.url?.path == "/api/auth/ws-ticket" ? (200, #"{"ticket":"t1"}"#) : (404, #"{"detail":"Not Found"}"#)
    }

    private func events(_ stream: SpeechStream) async -> [SpeechEvent] {
        var all: [SpeechEvent] = []
        for await event in stream.events { all.append(event) }
        return all
    }

    @Test func aClipComesBackForTheBotsVoice() async throws {
        let http = ScriptedHTTP { _ in
            (200, #"{"ok":true,"data_url":"data:audio/mpeg;base64,AQID","mime_type":"audio/mpeg","provider":"edge"}"#)
        }
        let clip = try await speaker(http).speak("Backups finished.", profile: "ops")
        #expect(clip == SpokenClip(audio: Data([1, 2, 3]), mimeType: "audio/mpeg"))
        #expect(clip.fileExtension == "mp3")
        let request = try #require(http.requests.first)
        #expect(request.url?.path == "/api/audio/speak")
        #expect(request.url?.query == "profile=ops")
        #expect(request.httpMethod == "POST")
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        #expect(body["text"] == "Backups finished.")
    }

    @Test func withoutABotTheGatewaysOwnVoiceSpeaks() async throws {
        let http = ScriptedHTTP { _ in (200, #"{"ok":true,"data_url":"data:audio/wav;base64,AQID"}"#) }
        let clip = try await speaker(http).speak("Hi.", profile: nil)
        #expect(clip.mimeType == "audio/wav")
        #expect(http.requests.first?.url?.query == nil)
    }

    @Test func anEmptyClipIsAnError() async {
        let http = ScriptedHTTP { _ in (200, #"{"ok":true,"data_url":"data:audio/mpeg;base64,"}"#) }
        await #expect(throws: GatewayError.invalidResponse) { try await speaker(http).speak("Hi.", profile: "ops") }
    }

    @Test func hermesRefusalsAreSaidPlainly() {
        func problem(_ error: GatewayError) -> String { GatewaySpeaker.problem(for: error) }
        #expect(
            problem(
                .http(status: 400, message: "No TTS provider available. Enable Edge TTS with: pip install edge-tts"))
                == "This gateway has no text-to-speech set up. Set one up in Hermes, or use On-device.")
        #expect(
            problem(.http(status: 404, message: "Not Found"))
                == "Update Hermes on your gateway to use Gateway calls, or use On-device.")
        #expect(
            problem(.http(status: 400, message: "TTS configuration error (openai): bad voice"))
                == "The gateway couldn’t speak the reply: TTS configuration error (openai): bad voice")
        #expect(problem(.unreachable("offline")).hasPrefix("Your gateway isn’t reachable"))
        #expect(problem(.disconnected).hasPrefix("Your gateway isn’t reachable"))
    }

    @Test func callsSayWhatDictationSaysAboutSpeechToText() {
        let off = GatewayError.http(status: 400, message: "STT is disabled in config.yaml")
        #expect(
            GatewayTranscriber.problem(for: off, use: .call)
                == GatewayTranscriber.problem(for: off, use: .dictation))
        #expect(
            GatewayTranscriber.problem(for: GatewayError.http(status: 404, message: "Not Found"), use: .call)
                == "Update Hermes on your gateway to use Gateway calls, or use On-device.")
        #expect(GatewayTranscriber.problem(for: GatewayError.disconnected, use: .call).hasPrefix("Your gateway isn’t"))
        // Dictation keeps its own words for a lost gateway.
        #expect(GatewayTranscriber.problem(for: GatewayError.disconnected).hasPrefix("The gateway couldn’t transcribe"))
    }

    @Test func sentencesStreamInAndPCMStreamsBack() async throws {
        let socket = FakeSpeechSocket()
        socket.onSend = { socket, text in
            if text.contains("text") {
                socket.answer(.text(#"{"type":"start","sample_rate":22050,"channels":1}"#))
                socket.answer(.data(Data([1, 0, 2, 0])))
            }
            if text.contains("done") { socket.answer(.text(#"{"type":"end"}"#)) }
        }
        let opened = OpenedURLs()
        let stream = speaker(Self.ticket, socket: socket, opened: opened).stream(profile: "ops")
        stream.say("Backups finished.")
        stream.done()
        let heard = await events(stream)
        #expect(heard == [.start(sampleRate: 22050), .pcm(Data([1, 0, 2, 0])), .end])
        #expect(socket.frames == [#"{"text":"Backups finished."}"#, #"{"done":true}"#])
        let url = try #require(opened.urls.withLock { $0.first })
        #expect(url.scheme == "ws")
        #expect(url.path == "/api/audio/speak-stream")
        #expect(url.query == "profile=ops&ticket=t1")
    }

    /// Hermes forwards the provider's chunks as they come, and they split samples: each `.pcm`
    /// must still hold whole samples, or every one after the split plays as noise.
    @Test func oddSizedFramesComeOutAsWholeSamples() async {
        let wave = (0..<2000).map { Int16(12_000 * sin(Double($0) / 9)) }
        let bytes = wave.withUnsafeBufferPointer { Data(buffer: $0) }
        var chunks = [bytes.prefix(343)]
        var offset = 343
        while offset < bytes.count {
            chunks.append(bytes[offset..<min(offset + 1369, bytes.count)])
            offset += 1369
        }
        let socket = FakeSpeechSocket()
        socket.onSend = { socket, text in
            guard text.contains("done") else { return }
            socket.answer(.text(#"{"type":"start","sample_rate":24000}"#))
            for chunk in chunks { socket.answer(.data(Data(chunk))) }
            socket.answer(.text(#"{"type":"end"}"#))
        }
        let stream = speaker(Self.ticket, socket: socket).stream(profile: "ops")
        stream.say("Hi.")
        stream.done()
        var heard: [Int16] = []
        for event in await events(stream) {
            guard case .pcm(let pcm) = event else { continue }
            #expect(pcm.count.isMultiple(of: 2))
            // Read each piece on its own, as the call plays it.
            heard += stride(from: 0, to: pcm.count - 1, by: 2).map {
                Int16(
                    littleEndian: Int16(
                        bitPattern: UInt16(pcm[pcm.startIndex + $0]) | UInt16(pcm[pcm.startIndex + $0 + 1]) << 8))
            }
        }
        #expect(heard == wave)
    }

    @Test func aNewUtteranceNeverStartsOnHalfASample() {
        var joiner = PCMJoiner()
        #expect(joiner.add(Data([1, 2, 3])) == Data([1, 2]))
        #expect(joiner.add(Data([4])) == Data([3, 4]))
        #expect(joiner.add(Data([5])) == Data())
        joiner.reset()
        #expect(joiner.add(Data([6, 7])) == Data([6, 7]))
    }

    @Test func noiseIsToldFromSpeech() {
        let speech = (0..<4800).map { Int16(12_000 * sin(Double($0) / 9)) }
        // The same samples a byte out: what the app played before.
        let bytes = speech.withUnsafeBufferPointer { Data(buffer: $0) }
        let shifted = bytes.dropFirst().prefix(bytes.count - 2)
        let noise = stride(from: 0, to: shifted.count - 1, by: 2).map {
            Int16(
                bitPattern: UInt16(shifted[shifted.startIndex + $0]) | UInt16(shifted[shifted.startIndex + $0 + 1]) << 8
            )
        }
        #expect(PCMCheck.judge(speech) == .speech)
        #expect(PCMCheck.judge(noise) == .noise)
        #expect(PCMCheck.judge([Int16](repeating: 3, count: 4800)) == .quiet)
        #expect(PCMCheck.judge((0..<4800).map { Int16(100 * sin(Double($0))) }) == .quiet)
    }

    @Test func aGatewayThatCantStreamSaysFallBack() async {
        let socket = FakeSpeechSocket()
        socket.onSend = { socket, text in if text.contains("done") { socket.answer(.text(#"{"type":"fallback"}"#)) } }
        let stream = speaker(Self.ticket, socket: socket).stream(profile: "ops")
        stream.say("Hi.")
        stream.done()
        #expect(await events(stream) == [.fallback])
    }

    @Test func aSocketThatWontOpenMeansClips() async {
        let stream = speaker(Self.ticket).stream(profile: nil)
        stream.say("Hi.")
        #expect(await events(stream) == [.fallback])
    }

    @Test func stoppingCutsItOff() async {
        let socket = FakeSpeechSocket()
        let stream = speaker(Self.ticket, socket: socket).stream(profile: "ops")
        stream.say("A long reply.")
        stream.stop()
        #expect(await events(stream).isEmpty)
    }

    @Test func speechMessagesAreRead() {
        #expect(SpeechMessage(#"{"type":"start","sample_rate":24000}"#) == .start(24000))
        #expect(SpeechMessage(#"{"type":"start"}"#) == .start(24000))
        #expect(SpeechMessage(#"{"type":"end"}"#) == .end)
        #expect(SpeechMessage(#"{"type":"fallback"}"#) == .fallback)
        #expect(SpeechMessage("nope") == .unknown)
    }

    @Test func theDemoSpeaksWithoutAGateway() async throws {
        let speaker = GatewaySpeaker(auth: { nil }, isDemo: { true })
        let stream = speaker.stream(profile: "ops")
        stream.done()
        #expect(await events(stream) == [.end])
    }
}
