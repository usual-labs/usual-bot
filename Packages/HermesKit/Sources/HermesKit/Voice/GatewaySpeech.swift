import Foundation

/// Text to speech on the gateway, with whatever provider the profile is set up with (Hermes's
/// `tts` settings): sentences streamed in and 16-bit PCM streamed back over
/// `/api/audio/speak-stream`, or one whole clip from `POST /api/audio/speak`. Voice and speed are
/// the gateway's; neither route takes them.
///
/// `profile` is the Bot whose voice speaks; `nil` is the gateway's own profile.
@MainActor
public final class GatewaySpeaker {
    /// Cloud providers give up after 60 s; Hermes's own app allows at least 180 s for a clip.
    static let speakTimeout: TimeInterval = 180

    private let auth: @MainActor () -> AuthSession?
    private let isDemo: @MainActor () -> Bool
    private let makeSocket: SpeechSocketFactory

    init(
        auth: @escaping @MainActor () -> AuthSession?, isDemo: @escaping @MainActor () -> Bool = { false },
        makeSocket: @escaping SpeechSocketFactory = { URLSessionSpeechSocket(url: $0) }
    ) {
        self.auth = auth
        self.isDemo = isDemo
        self.makeSocket = makeSocket
    }

    /// `text` spoken as one clip, usually MP3.
    public func speak(_ text: String, profile: String?) async throws -> SpokenClip {
        struct Body: Encodable, Sendable { let text: String }
        struct Reply: Decodable, Sendable {
            let dataUrl: String?
            let mimeType: String?
        }
        #if DEBUG
            if isDemo() {
                guard let audio = await DemoMedia.voiceMemo(text) else { throw GatewayError.invalidResponse }
                return SpokenClip(audio: audio, mimeType: "audio/m4a")
            }
        #endif
        guard let auth = auth() else { throw GatewayError.disconnected }
        let reply = try await auth.json(
            Reply.self, path: "/api/audio/speak" + Self.query(profile), method: "POST", body: Body(text: text),
            timeout: Self.speakTimeout)
        guard let clip = reply.dataUrl.flatMap({ SpokenClip(dataURL: $0, mimeType: reply.mimeType) }) else {
            throw GatewayError.invalidResponse
        }
        return clip
    }

    /// A reply spoken as it's written: `say` each sentence, then `done`. Its events give the audio;
    /// `.fallback` means the gateway couldn't stream (or the socket wouldn't open), and the
    /// sentences should go to `speak` instead.
    public func stream(profile: String?) -> SpeechStream {
        #if DEBUG
            if isDemo() { return SpeechStream(demo: ()) }
        #endif
        let auth = auth()
        let makeSocket = makeSocket
        return SpeechStream {
            guard let auth else { throw GatewayError.disconnected }
            let ticket = try await auth.webSocketTicket()
            return try await makeSocket(auth.gateway.speakStreamURL(profile: profile, ticket: ticket))
        }
    }

    /// Keeps the gateway's local voice loaded while a call is on (`/api/audio/tts-lease`; nothing
    /// for cloud providers). Best effort.
    public func warmUp(_ lease: String, active: Bool, profile: String?) {
        struct Body: Encodable, Sendable {
            let lease: String
            let active: Bool
        }
        struct Reply: Decodable {}
        guard !isDemo(), let auth = auth() else { return }
        let path = "/api/audio/tts-lease" + Self.query(profile)
        Task {
            _ = try? await auth.json(Reply.self, path: path, method: "POST", body: Body(lease: lease, active: active))
        }
    }

    /// What to tell someone when the gateway can't speak, in the words dictation's failures use.
    public nonisolated static func problem(for error: any Error) -> String {
        if let unreachable = GatewayTranscriber.unreachableProblem(error) { return unreachable }
        if case GatewayError.http(let status, let message) = error {
            let detail = message ?? ""
            if detail.localizedCaseInsensitiveContains("no tts provider") {
                return String(
                    localized: "This gateway has no text-to-speech set up. Set one up in Hermes, or use On-device.")
            }
            if status == 404, message == nil || detail == "Not Found" {
                return String(localized: "Update Hermes on your gateway to use Gateway calls, or use On-device.")
            }
            if !detail.isEmpty { return String(localized: "The gateway couldn’t speak the reply: \(detail)") }
        }
        return String(localized: "The gateway couldn’t speak the reply. \(error.localizedDescription)")
    }

    private static func query(_ profile: String?) -> String {
        guard let profile, !profile.isEmpty else { return "" }
        return "?profile=" + (profile.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? profile)
    }
}

/// A whole clip of speech, as the gateway's `data:` URL held it.
public struct SpokenClip: Sendable, Equatable {
    public let audio: Data
    public let mimeType: String

    public init(audio: Data, mimeType: String) {
        self.audio = audio
        self.mimeType = mimeType
    }

    init?(dataURL: String, mimeType: String?) {
        guard dataURL.hasPrefix("data:"), let comma = dataURL.firstIndex(of: ","),
            let audio = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])), !audio.isEmpty
        else { return nil }
        let header = dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5)..<comma]
        let type = header.split(separator: ";").first.map(String.init) ?? ""
        self.init(audio: audio, mimeType: mimeType ?? (type.isEmpty ? "audio/mpeg" : type))
    }

    /// The file extension AVFoundation needs to read it.
    public var fileExtension: String {
        switch mimeType {
        case "audio/wav", "audio/x-wav", "audio/wave": "wav"
        case "audio/ogg", "audio/opus": "ogg"
        case "audio/flac": "flac"
        case "audio/m4a", "audio/mp4", "audio/aac": "m4a"
        default: "mp3"
        }
    }
}

/// What the speak stream gives back.
public enum SpeechEvent: Sendable, Equatable {
    /// The audio's format: 16-bit little-endian mono PCM at this rate.
    case start(sampleRate: Double)
    case pcm(Data)
    /// Everything said has been sent.
    case end
    /// No audio could be made this way; use `GatewaySpeaker.speak`.
    case fallback
}

/// One reply's speech: sentences in, audio out.
public final class SpeechStream: Sendable {
    private enum Outgoing: Sendable {
        case text(String), done, stop
    }

    public let events: AsyncStream<SpeechEvent>
    private let output: AsyncStream<SpeechEvent>.Continuation
    private let input: AsyncStream<Outgoing>.Continuation
    private let task: Task<Void, Never>

    init(open: @escaping @Sendable () async throws -> any SpeechSocket) {
        let (outgoing, input) = AsyncStream<Outgoing>.makeStream()
        let (events, output) = AsyncStream<SpeechEvent>.makeStream()
        self.input = input
        self.events = events
        self.output = output
        task = Task { await Self.run(outgoing: outgoing, open: open, output: output) }
    }

    #if DEBUG
        /// The demo's: each sentence said by this device's voice, as the gateway would stream it.
        init(demo: Void) {
            let (outgoing, input) = AsyncStream<Outgoing>.makeStream()
            let (events, output) = AsyncStream<SpeechEvent>.makeStream()
            self.input = input
            self.events = events
            self.output = output
            task = Task {
                var started = false
                for await message in outgoing {
                    guard case .text(let sentence) = message else {
                        if case .done = message { output.yield(.end) }
                        break
                    }
                    guard let clip = await DemoMedia.voiceMemo(sentence),
                        let (rate, pcm) = DemoMedia.pcm16(fromM4A: clip)
                    else { continue }
                    if !started { output.yield(.start(sampleRate: rate)) }
                    started = true
                    output.yield(.pcm(pcm))
                }
                output.finish()
            }
        }
    #endif

    /// Adds a sentence to say.
    public func say(_ text: String) { input.yield(.text(text)) }

    /// No more sentences: the stream ends once they're spoken.
    public func done() {
        input.yield(.done)
        input.finish()
    }

    /// Cuts it off: nothing more is said.
    public func stop() {
        input.yield(.stop)
        input.finish()
        task.cancel()
        output.finish()
    }

    private static func run(
        outgoing: AsyncStream<Outgoing>, open: @Sendable () async throws -> any SpeechSocket,
        output: AsyncStream<SpeechEvent>.Continuation
    ) async {
        defer { output.finish() }
        guard let socket = try? await open() else {
            output.yield(.fallback)
            return
        }
        defer { socket.close() }
        await withTaskCancellationHandler {
            // `true` from the reader, which alone knows when the speech is over.
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await message in outgoing {
                        let frame: String
                        switch message {
                        case .text(let text): frame = Self.json(["text": .string(text)])
                        case .done: frame = #"{"done":true}"#
                        case .stop: frame = #"{"stop":true}"#
                        }
                        guard (try? await socket.send(text: frame)) != nil else { return false }
                    }
                    return false
                }
                group.addTask {
                    var heardAudio = false
                    while let frame = try? await socket.receive() {
                        switch frame {
                        case .data(let pcm):
                            heardAudio = true
                            output.yield(.pcm(pcm))
                        case .text(let text):
                            switch SpeechMessage(text) {
                            case .start(let rate): output.yield(.start(sampleRate: rate))
                            case .end:
                                output.yield(.end)
                                return true
                            case .fallback:
                                output.yield(.fallback)
                                return true
                            case .unknown: continue
                            }
                        }
                    }
                    // A socket that closed before any audio is a gateway that can't stream.
                    if !heardAudio { output.yield(.fallback) }
                    return true
                }
                for await readerEnded in group where readerEnded { break }
                // The reader ended the speech: closing ends the writer, which waits for sentences.
                socket.close()
                group.cancelAll()
            }
        } onCancel: {
            socket.close()
        }
    }

    private static func json(_ object: [String: JSONValue]) -> String {
        (try? JSONEncoder().encode(object)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// The speak stream's JSON text frames.
enum SpeechMessage: Equatable {
    case start(Double)
    case end
    case fallback
    case unknown

    init(_ text: String) {
        let json = try? JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))
        switch json?["type"]?.stringValue {
        case "start": self = .start(Self.rate(json?["sample_rate"]))
        case "end": self = .end
        case "fallback": self = .fallback
        default: self = .unknown
        }
    }

    /// Hermes streams at 24 kHz unless the provider says otherwise.
    private static func rate(_ value: JSONValue?) -> Double {
        if case .number(let rate) = value, rate > 0 { return rate }
        return 24_000
    }
}

/// A frame from the speak stream: JSON text, or audio.
public enum SpeechFrame: Sendable, Equatable {
    case text(String)
    case data(Data)
}

/// A WebSocket that sends text and receives text and audio: the speak stream.
/// `URLSessionWebSocketTask` in the app; a script in tests.
public protocol SpeechSocket: Sendable {
    func send(text: String) async throws
    /// The next frame. Throws once the socket is closed.
    func receive() async throws -> SpeechFrame
    func close()
}

typealias SpeechSocketFactory = @Sendable (URL) async throws -> any SpeechSocket

final class URLSessionSpeechSocket: SpeechSocket, @unchecked Sendable {
    // @unchecked: URLSessionWebSocketTask is safe to use from any thread.
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession = .shared) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        task = session.webSocketTask(with: request)
        task.resume()
    }

    func send(text: String) async throws { try await task.send(.string(text)) }

    func receive() async throws -> SpeechFrame {
        switch try await task.receive() {
        case .string(let text): return .text(text)
        case .data(let data): return .data(data)
        @unknown default: throw GatewayError.invalidResponse
        }
    }

    func close() { task.cancel(with: .normalClosure, reason: nil) }
}

extension GatewayAddress {
    /// The speak socket, authenticated by a single-use ticket like the transcribe stream.
    func speakStreamURL(profile: String?, ticket: String) -> URL {
        var components = URLComponents(url: url("/api/audio/speak-stream"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        var items = [URLQueryItem(name: "ticket", value: ticket)]
        if let profile, !profile.isEmpty { items.insert(URLQueryItem(name: "profile", value: profile), at: 0) }
        components.queryItems = items
        return components.url!
    }
}
