import Foundation
import Testing

@testable import HermesKit

@MainActor
struct VoiceLiveTests {
    private func service(_ http: ScriptedHTTP) -> VoiceLiveService {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        return VoiceLiveService(auth: { auth })
    }

    @Test func statusSaysWhetherGPTLiveCanStart() async throws {
        let http = ScriptedHTTP { _ in
            (200, #"{"ok":true,"mode":"chained","available":false,"reason":"no OpenAI API key","model":"gpt-live-1","voice":"marin"}"#)
        }
        let status = try await service(http).status(profile: "ops")
        #expect(status == VoiceLiveStatus(mode: "chained", available: false, reason: "no OpenAI API key", model: "gpt-live-1", voice: "marin"))
        #expect(http.requests.first?.url?.path == "/api/audio/voice-live/status")
        #expect(http.requests.first?.url?.query == "profile=ops")
    }

    @Test func theOfferIsExchangedForTheAnswer() async throws {
        let http = ScriptedHTTP { _ in
            (200, #"{"ok":true,"session":{"id":"sess_1"},"transport":{"type":"webrtc","sdp":"v=0 answer\r\n"}}"#)
        }
        let answer = try await service(http).answer(offer: "v=0 offer\r\n", history: [], profile: "ops")
        #expect(answer == "v=0 answer\r\n")
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        // Byte-exact, trailing CRLF included: the vendor's SDP parser needs it.
        #expect(body["sdp"] == "v=0 offer\r\n")
        #expect(body["history"] == [])
    }

    @Test func historyIsTheLatestTextTurnsOldestFirst() {
        let thread = ChatThread.sample(
            "ops",
            state: ThreadState(
                history: [
                    HistoryMessage(role: "user", text: "How are the servers?"),
                    HistoryMessage(role: "tool", name: "terminal", context: "uptime"),
                    HistoryMessage(role: "assistant", text: "All   healthy."),
                ], running: false))
        #expect(
            thread.liveHistory() == [
                ["type": "message", "role": "user", "content": [["type": "input_text", "text": "How are the servers?"]]],
                ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "All healthy."]]],
            ])
        #expect(thread.liveHistory(maxMessages: 1) == [
            ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "All healthy."]]]
        ])
    }

    @Test func aDelegationIsAVoiceLiveTurn() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "ops", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }

        async let sent: Void = thread.delegate("check the backups", spokenContext: "User: check the backups")
        let params = try await gateway.answer(1, method: "prompt.submit", result: ["status": "streaming"])
        await sent
        #expect(
            params == [
                "session_id": "live-1", "text": "check the backups", "surface": "voice-live",
                "voice_context": "User: check the backups",
            ])
        #expect(thread.state.items.map(\.content) == [.user("check the backups")])
    }
}
