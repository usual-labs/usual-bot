import Foundation

/// Speech to text on the gateway, with whatever provider the profile is set up with (Hermes's
/// `stt` settings): a whole recording uploaded (`POST /api/audio/transcribe`), or live words over
/// `/api/audio/transcribe-stream` where the gateway can stream. The app never asks for the voice
/// settings (`/api/audio/voice-config`): off the Webapp that answer carries provider keys.
///
/// `profile` is the Bot whose settings transcribe; `nil` is the gateway's own profile.
@MainActor
public final class GatewayTranscriber {
    /// Hermes refuses uploads over 25 MB.
    public static let maxUploadBytes = 25 * 1024 * 1024
    /// Local Whisper's first use downloads and loads its model; Hermes's own app allows 180 s.
    static let uploadTimeout: TimeInterval = 180

    private let auth: @MainActor () -> AuthSession?
    private let isDemo: @MainActor () -> Bool
    private let makeSocket: TranscriptionSocketFactory

    init(
        auth: @escaping @MainActor () -> AuthSession?, isDemo: @escaping @MainActor () -> Bool = { false },
        makeSocket: @escaping TranscriptionSocketFactory = { URLSessionTranscriptionSocket(url: $0) }
    ) {
        self.auth = auth
        self.isDemo = isDemo
        self.makeSocket = makeSocket
    }

    /// The words in a recording. An empty string means no speech was heard.
    public func transcribe(_ audio: Data, mimeType: String, profile: String?) async throws -> String {
        struct Body: Encodable, Sendable {
            let dataUrl: String
            let mimeType: String
        }
        struct Reply: Decodable { let transcript: String? }
        if isDemo() {
            try await Task.sleep(for: .seconds(1.2))
            return String(localized: "Can you check whether last night’s backup finished?")
        }
        guard let auth = auth() else { throw GatewayError.disconnected }
        let reply = try await auth.json(
            Reply.self, path: "/api/audio/transcribe" + Self.query(profile), method: "POST",
            body: Body(dataUrl: "data:\(mimeType);base64,\(audio.base64EncodedString())", mimeType: mimeType),
            timeout: Self.uploadTimeout)
        return reply.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Live words while you speak. Push 16 kHz mono 16-bit PCM as it's recorded; `finish` gives the
    /// transcript, or `nil` when the gateway can't stream (the usual case: Hermes streams only with
    /// `stt.streaming` on and an OpenAI, xAI or ElevenLabs provider), and the recording is uploaded
    /// instead. Audio pushed before the socket opens waits for it.
    public func stream(profile: String?, onPartial: @escaping @MainActor (String) -> Void) -> TranscriptionStream {
        let auth = auth()
        let isDemo = isDemo()
        let makeSocket = makeSocket
        return TranscriptionStream(onPartial: onPartial) {
            guard !isDemo, let auth else { throw GatewayError.disconnected }
            let ticket = try await auth.webSocketTicket()
            return try await makeSocket(auth.gateway.transcribeStreamURL(profile: profile, ticket: ticket))
        }
    }

    /// Asks the gateway to load its local speech model while you talk, so the transcript doesn't
    /// wait for it (`/api/audio/stt-lease`; nothing for cloud providers). Best effort.
    public func warmUp(_ lease: String, active: Bool, profile: String?) {
        struct Body: Encodable, Sendable {
            let lease: String
            let active: Bool
        }
        struct Reply: Decodable {}
        guard !isDemo(), let auth = auth() else { return }
        let path = "/api/audio/stt-lease" + Self.query(profile)
        Task {
            _ = try? await auth.json(Reply.self, path: path, method: "POST", body: Body(lease: lease, active: active))
        }
    }

    /// What gateway speech is for: the words differ where they name it.
    public enum Use: Sendable {
        case dictation, call
    }

    /// What to tell someone when gateway transcription fails, with the two refusals Hermes gives
    /// most in plain words.
    public nonisolated static func problem(for error: any Error, use: Use = .dictation) -> String {
        if use == .call, let unreachable = unreachableProblem(error) { return unreachable }
        if case GatewayError.http(let status, let message) = error {
            let detail = message ?? ""
            if detail.localizedCaseInsensitiveContains("stt is disabled") {
                return String(
                    localized: "Speech-to-text is off on this gateway. Turn it on in Hermes, or use On-device.")
            }
            if detail.localizedCaseInsensitiveContains("no stt provider") {
                return String(
                    localized: "This gateway has no speech-to-text set up. Set one up in Hermes, or use On-device.")
            }
            // A route this Hermes doesn't have answers FastAPI's plain "Not Found".
            if status == 404, message == nil || detail == "Not Found" {
                return use == .call
                    ? String(localized: "Update Hermes on your gateway to use Gateway calls, or use On-device.")
                    : String(localized: "Update Hermes on your gateway to use Gateway dictation, or use On-device.")
            }
            if !detail.isEmpty { return String(localized: "The gateway couldn’t transcribe that: \(detail)") }
        }
        return String(localized: "The gateway couldn’t transcribe that. \(error.localizedDescription)")
    }

    /// A call that loses its gateway says so, rather than the transport's own words.
    nonisolated static func unreachableProblem(_ error: any Error) -> String? {
        switch error as? GatewayError {
        case .unreachable, .disconnected, .timedOut:
            String(
                localized:
                    "Your gateway isn’t reachable, so the call can’t go on. Use On-device, or try again when it’s back."
            )
        default: nil
        }
    }

    private static func query(_ profile: String?) -> String {
        guard let profile, !profile.isEmpty else { return "" }
        return "?profile=" + (profile.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? profile)
    }
}

/// One live transcription: audio in from any thread, partial words out on the main actor.
public final class TranscriptionStream: Sendable {
    /// How long to wait for the final words after the recording ends. Hermes gives its provider 20 s.
    static let finishTimeout: Duration = .seconds(30)

    private let input: AsyncStream<Data>.Continuation
    private let task: Task<String?, Never>

    init(
        onPartial: @escaping @MainActor (String) -> Void,
        open: @escaping @Sendable () async throws -> any TranscriptionSocket
    ) {
        let (audio, input) = AsyncStream<Data>.makeStream()
        self.input = input
        task = Task { await Self.run(audio: audio, open: open, onPartial: onPartial) }
    }

    /// Adds recorded audio: 16 kHz mono 16-bit little-endian PCM, in any chunk size.
    public func push(_ pcm: Data) {
        input.yield(pcm)
    }

    /// Ends the recording and waits for the transcript; `nil` if the stream couldn't give one.
    public func finish() async -> String? {
        input.finish()
        let task = task
        return await withTaskGroup(of: String??.self) { group in
            group.addTask { .some(await task.value) }
            group.addTask {
                try? await Task.sleep(for: Self.finishTimeout)
                return .none
            }
            let first = await group.next() ?? .none
            group.cancelAll()
            if case .some(let transcript) = first { return transcript }
            task.cancel()
            return nil
        }
    }

    /// Drops the recording and closes the socket.
    public func cancel() {
        input.finish()
        task.cancel()
    }

    private static func run(
        audio: AsyncStream<Data>, open: @Sendable () async throws -> any TranscriptionSocket,
        onPartial: @escaping @MainActor (String) -> Void
    ) async -> String? {
        guard let socket = try? await open() else { return nil }
        defer { socket.close() }
        return await withTaskCancellationHandler {
            await withTaskGroup(of: String??.self) { group in
                group.addTask {
                    do {
                        try await socket.send(text: #"{"sample_rate":16000}"#)
                        for await chunk in audio { try await socket.send(data: chunk) }
                        try Task.checkCancellation()
                        try await socket.send(text: #"{"eos":true}"#)
                    } catch {
                        return .some(nil)
                    }
                    return .none  // The answer comes from the reader.
                }
                group.addTask {
                    while let message = try? await socket.receive() {
                        switch StreamMessage(message) {
                        case .partial(let text): await onPartial(text)
                        case .final(let transcript): return .some(transcript)
                        case .error: return .some(nil)
                        case .unknown: continue
                        }
                    }
                    return .some(nil)
                }
                for await result in group {
                    if case .some(let transcript) = result {
                        // Closing first: a reader waiting on the socket ends only when it closes,
                        // and the group waits for it.
                        socket.close()
                        group.cancelAll()
                        return transcript
                    }
                }
                return nil
            }
        } onCancel: {
            socket.close()
        }
    }
}

/// What the transcribe stream sends: JSON text frames.
enum StreamMessage: Equatable {
    case partial(String)
    case final(String)
    /// Also how a gateway without live speech-to-text answers, at once.
    case error(String)
    case unknown

    init(_ text: String) {
        let json = try? JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))
        switch json?["type"]?.stringValue {
        case "partial": self = .partial(json?["text"]?.stringValue ?? "")
        case "final":
            self = .final(json?["transcript"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        case "error": self = .error(json?["message"]?.stringValue ?? "")
        default: self = .unknown
        }
    }
}

/// A WebSocket that sends text and binary frames and receives text: the transcribe stream.
/// `URLSessionWebSocketTask` in the app; a script in tests.
public protocol TranscriptionSocket: Sendable {
    func send(text: String) async throws
    func send(data: Data) async throws
    /// The next text frame. Throws once the socket is closed.
    func receive() async throws -> String
    func close()
}

typealias TranscriptionSocketFactory = @Sendable (URL) async throws -> any TranscriptionSocket

final class URLSessionTranscriptionSocket: TranscriptionSocket, @unchecked Sendable {
    // @unchecked: URLSessionWebSocketTask is safe to use from any thread.
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession = .shared) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        task = session.webSocketTask(with: request)
        task.resume()
    }

    func send(text: String) async throws { try await task.send(.string(text)) }

    func send(data: Data) async throws { try await task.send(.data(data)) }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: throw GatewayError.invalidResponse
        }
    }

    func close() { task.cancel(with: .normalClosure, reason: nil) }
}

extension GatewayAddress {
    /// The live transcription socket, authenticated by a single-use ticket like the app's own.
    func transcribeStreamURL(profile: String?, ticket: String) -> URL {
        var components = URLComponents(url: url("/api/audio/transcribe-stream"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        var items = [URLQueryItem(name: "ticket", value: ticket)]
        if let profile, !profile.isEmpty { items.insert(URLQueryItem(name: "profile", value: profile), at: 0) }
        components.queryItems = items
        return components.url!
    }
}
