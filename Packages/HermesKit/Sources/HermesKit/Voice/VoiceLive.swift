import Foundation

/// Whether a profile's calls can use GPT-Live, OpenAI's full-duplex voice model, which hands real
/// work to Hermes (`GET /api/audio/voice-live/status`). Nothing secret: the key stays on the gateway.
public struct VoiceLiveStatus: Decodable, Equatable, Sendable {
    /// `chained` (speech to text, a turn, text to speech) or `gpt-live`: what the profile selected.
    public let mode: String
    /// The gateway has an OpenAI key, so a GPT-Live session can start.
    public let available: Bool
    /// Why not, when it can't.
    public let reason: String?
    public let model: String
    public let voice: String

    public init(mode: String, available: Bool, reason: String? = nil, model: String = "", voice: String = "") {
        self.mode = mode
        self.available = available
        self.reason = reason
        self.model = model
        self.voice = voice
    }
}

/// GPT-Live sessions through the gateway: the app's WebRTC offer goes to the gateway, which opens
/// the session with its own OpenAI key and returns the answer. Audio then flows between the app and
/// OpenAI directly; the gateway only sees the turns the voice delegates to Hermes.
@MainActor
public final class VoiceLiveService {
    private let auth: @MainActor () -> AuthSession?

    init(auth: @escaping @MainActor () -> AuthSession?) {
        self.auth = auth
    }

    public func status(profile: String) async throws -> VoiceLiveStatus {
        guard let auth = auth() else { throw GatewayError.disconnected }
        return try await auth.json(VoiceLiveStatus.self, path: "/api/audio/voice-live/status?profile=\(escape(profile))")
    }

    /// Exchanges the WebRTC `offer` for the session's SDP answer. `history` seeds the voice with the
    /// chat so far (`ChatThread.liveHistory`).
    public func answer(offer: String, history: JSONValue, profile: String) async throws -> String {
        struct Body: Encodable, Sendable {
            let sdp: String
            let history: JSONValue
        }
        struct Transport: Decodable { let sdp: String }
        struct Reply: Decodable { let transport: Transport? }
        guard let auth = auth() else { throw GatewayError.disconnected }
        let reply = try await auth.json(
            Reply.self, path: "/api/audio/voice-live/session?profile=\(escape(profile))", method: "POST",
            body: Body(sdp: offer, history: history))
        guard let sdp = reply.transport?.sdp, !sdp.isEmpty else { throw GatewayError.invalidResponse }
        return sdp
    }

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? component
    }
}

extension ChatThread {
    /// The chat so far as GPT-Live's seed history: the latest text turns, newest last, at most 24
    /// messages and about 6,000 characters (as the official app sends).
    public func liveHistory(maxMessages: Int = 24, maxCharacters: Int = 6_000) -> JSONValue {
        var budget = maxCharacters
        var messages: [JSONValue] = []
        for item in state.items.reversed() {
            let role: String
            let text: String
            switch item.content {
            case .user(let words):
                role = "user"
                text = AttachmentRef.split(words).text
            case .assistant(let words):
                role = "assistant"
                text = words
            default:
                continue
            }
            let flat = String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(1_200))
            guard !flat.isEmpty else { continue }
            guard messages.count < maxMessages, budget - flat.count >= 0 else { break }
            budget -= flat.count
            messages.insert(
                [
                    "type": "message", "role": .string(role),
                    "content": [["type": .string(role == "assistant" ? "output_text" : "input_text"), "text": .string(flat)]],
                ], at: 0)
        }
        return .array(messages)
    }

    /// Something the voice handed to Hermes: sent as your message with the recent spoken exchange
    /// (`voice_context`, for the model only) on the `voice-live` surface, so Hermes answers for
    /// speaking. A reply still running is stopped first: the newest request wins.
    public func delegate(_ prompt: String, spokenContext: String) async {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, canSend else { return }
        if state.isRunning {
            stop()
            for _ in 0..<50 where state.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
        }
        guard let sessionID, let channel = channel() else { return }
        state.sendLocally(prompt)
        await submit(
            prompt, sessionID: sessionID, channel: channel,
            extra: ["surface": "voice-live", "voice_context": .string(String(spokenContext.suffix(6_000)))])
    }
}
