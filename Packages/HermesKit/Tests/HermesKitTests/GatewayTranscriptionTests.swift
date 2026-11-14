import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// The transcribe stream's far end: records what the app sends and answers from a script.
// @unchecked: the stream's one reader is the only caller of `receive`.
private final class FakeTranscriptionSocket: TranscriptionSocket, @unchecked Sendable {
    enum Sent: Equatable {
        case text(String)
        case data(Data)
    }

    private let sent = Mutex<[Sent]>([])
    private let replies: AsyncStream<String>
    private let reply: AsyncStream<String>.Continuation

    init() {
        (replies, reply) = AsyncStream<String>.makeStream()
    }

    var frames: [Sent] { sent.withLock { $0 } }

    /// Sends a frame to the app.
    func answer(_ text: String) { reply.yield(text) }

    func send(text: String) async throws {
        sent.withLock { $0.append(.text(text)) }
        if text.contains("eos") { onEnd?(self) }
    }

    func send(data: Data) async throws { sent.withLock { $0.append(.data(data)) } }

    private lazy var iterator = replies.makeAsyncIterator()

    func receive() async throws -> String {
        guard let text = await iterator.next() else { throw GatewayError.disconnected }
        return text
    }

    func close() { reply.finish() }

    /// Called when the app ends the recording, to send the final words.
    var onEnd: ((FakeTranscriptionSocket) -> Void)?
}

@MainActor
private final class Heard {
    var words: [String] = []
}

private final class OpenedSockets: Sendable {
    let urls = Mutex<[URL]>([])
}

@MainActor
struct GatewayTranscriptionTests {
    private func auth(_ http: ScriptedHTTP) -> AuthSession {
        AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
    }

    private func transcriber(
        _ http: ScriptedHTTP, socket: (any TranscriptionSocket)? = nil, opened: OpenedSockets = OpenedSockets()
    ) -> GatewayTranscriber {
        let auth = auth(http)
        return GatewayTranscriber(
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

    @Test func aRecordingIsUploadedAsADataURLForTheBot() async throws {
        let http = ScriptedHTTP { _ in (200, #"{"ok":true,"transcript":" Check the backups. ","provider":"local"}"#) }
        let words = try await transcriber(http).transcribe(Data([1, 2, 3]), mimeType: "audio/m4a", profile: "ops")
        #expect(words == "Check the backups.")
        let request = try #require(http.requests.first)
        #expect(request.url?.path == "/api/audio/transcribe")
        #expect(request.url?.query == "profile=ops")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == GatewayTranscriber.uploadTimeout)
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        #expect(body["data_url"] == "data:audio/m4a;base64,AQID")
        #expect(body["mime_type"] == "audio/m4a")
    }

    @Test func withoutABotTheGatewaysOwnProfileTranscribes() async throws {
        let http = ScriptedHTTP { _ in (200, #"{"ok":true,"transcript":""}"#) }
        let words = try await transcriber(http).transcribe(Data([1]), mimeType: "audio/m4a", profile: nil)
        #expect(words.isEmpty)
        #expect(http.requests.first?.url?.query == nil)
    }

    @Test func hermesRefusalsAreSaidPlainly() {
        func problem(_ status: Int, _ message: String?) -> String {
            GatewayTranscriber.problem(for: GatewayError.http(status: status, message: message))
        }
        #expect(
            problem(400, "STT is disabled in config.yaml (stt.enabled: false).")
                == "Speech-to-text is off on this gateway. Turn it on in Hermes, or use On-device.")
        #expect(
            problem(400, "No STT provider available. Install faster-whisper for free local transcription…")
                == "This gateway has no speech-to-text set up. Set one up in Hermes, or use On-device.")
        #expect(
            problem(404, "Not Found") == "Update Hermes on your gateway to use Gateway dictation, or use On-device.")
        // A missing profile is a 404 too, with its own words.
        #expect(
            problem(404, "Profile 'ghost' does not exist.")
                == "The gateway couldn’t transcribe that: Profile 'ghost' does not exist.")
        #expect(
            problem(400, "Audio recording is empty") == "The gateway couldn’t transcribe that: Audio recording is empty"
        )
    }

    @Test func liveWordsArriveAsYouSpeakAndTheFinalWordsEndIt() async throws {
        let socket = FakeTranscriptionSocket()
        socket.onEnd = { $0.answer(#"{"type":"final","transcript":" Check the backups. ","provider":"openai"}"#) }
        let opened = OpenedSockets()
        let heard = Heard()
        let stream = transcriber(Self.ticket, socket: socket, opened: opened)
            .stream(profile: "ops") { heard.words.append($0) }
        stream.push(Data([1, 0]))
        socket.answer(#"{"type":"partial","text":"Check the"}"#)
        stream.push(Data([2, 0]))
        // The partial reaches the main actor before the recording ends.
        try await waitUntilOnMain { !heard.words.isEmpty }
        let words = await stream.finish()
        #expect(words == "Check the backups.")
        #expect(heard.words == ["Check the"])
        #expect(
            socket.frames == [
                .text(#"{"sample_rate":16000}"#), .data(Data([1, 0])), .data(Data([2, 0])), .text(#"{"eos":true}"#),
            ])
        let url = try #require(opened.urls.withLock { $0.first })
        #expect(url.scheme == "ws")
        #expect(url.path == "/api/audio/transcribe-stream")
        #expect(url.query == "profile=ops&ticket=t1")
    }

    @Test func aGatewayThatCantStreamSaysSoAndTheRecordingIsUploaded() async {
        let socket = FakeTranscriptionSocket()
        socket.answer(#"{"type":"error","message":"no live STT for the configured provider"}"#)
        let stream = transcriber(Self.ticket, socket: socket).stream(profile: "ops") { _ in }
        stream.push(Data([1, 0]))
        #expect(await stream.finish() == nil)
    }

    @Test func aSocketThatWontOpenMeansUploading() async {
        let stream = transcriber(Self.ticket).stream(profile: nil) { _ in }
        stream.push(Data([1, 0]))
        #expect(await stream.finish() == nil)
    }

    @Test func aStreamThatErrsAfterTheRecordingMeansUploading() async {
        let socket = FakeTranscriptionSocket()
        socket.onEnd = { $0.answer(#"{"type":"error","message":"provider never finalized the transcript"}"#) }
        let stream = transcriber(Self.ticket, socket: socket).stream(profile: "ops") { _ in }
        #expect(await stream.finish() == nil)
    }

    @Test func theDemoTranscribesWithoutAGateway() async throws {
        let transcriber = GatewayTranscriber(auth: { nil }, isDemo: { true })
        let words = try await transcriber.transcribe(Data([1]), mimeType: "audio/m4a", profile: "ops")
        #expect(!words.isEmpty)
        #expect(await transcriber.stream(profile: "ops") { _ in }.finish() == nil)
    }

    @Test func streamMessagesAreRead() {
        #expect(StreamMessage(#"{"type":"partial","text":"Hi"}"#) == .partial("Hi"))
        #expect(StreamMessage(#"{"type":"final","transcript":"Hi there "}"#) == .final("Hi there"))
        #expect(StreamMessage(#"{"type":"error","message":"nope"}"#) == .error("nope"))
        #expect(StreamMessage("not json") == .unknown)
    }
}
