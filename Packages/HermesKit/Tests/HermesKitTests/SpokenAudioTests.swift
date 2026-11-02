import Foundation
import Testing

@testable import HermesKit

struct SpokenAudioTests {
    private func event(_ type: String, _ payload: JSONValue) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "s1", seq: nil, payload: payload)
    }

    private func transcripts(_ state: ThreadState, _ paths: [String]) -> [String: String] {
        let index = state.items.lastIndex { if case .assistant = $0.content { true } else { false } }
        return SpokenAudio.transcripts(in: state.items, replyAt: index ?? 0, audioPaths: paths)
    }

    @Test func aLiveCallNamesItsFileSoItsTextIsTheTranscript() {
        var state = ThreadState()
        state.apply(event("message.start", [:]))
        state.apply(
            event("tool.start", ["tool_id": "t1", "name": "text_to_speech", "args": ["text": "Good morning."]]))
        state.apply(
            event(
                "tool.complete",
                [
                    "tool_id": "t1", "name": "text_to_speech", "args": ["text": "Good morning."],
                    "result": ["success": true, "file_path": "/c/tts_1.mp3", "file_paths": ["/c/tts_1.mp3"]],
                ]))
        state.apply(event("message.complete", ["text": "Here.\nMEDIA:/c/other.mp3\nMEDIA:/c/tts_1.mp3"]))

        #expect(transcripts(state, ["/c/other.mp3", "/c/tts_1.mp3"]) == ["/c/tts_1.mp3": "Good morning."])
    }

    @Test func historyPairsCallsWithAudioInOrderOnlyWhenTheCountsMatch() {
        let history = [
            HistoryMessage(role: "user", text: "Read both"),
            HistoryMessage(role: "tool", name: "text_to_speech", toolCallId: "a", args: ["text": "One."]),
            HistoryMessage(role: "tool", name: "terminal", context: "ls", toolCallId: "b"),
            HistoryMessage(role: "tool", name: "text_to_speech", toolCallId: "c", args: ["text": "Two."]),
            HistoryMessage(role: "assistant", text: "MEDIA:/c/tts_a.mp3\nMEDIA:/c/tts_b.mp3"),
        ]
        let state = ThreadState(history: history, running: false)

        #expect(
            transcripts(state, ["/c/tts_a.mp3", "/c/tts_b.mp3"]) == ["/c/tts_a.mp3": "One.", "/c/tts_b.mp3": "Two."])
        // A third file, or a missing one: which text goes with which is a guess, so none shows.
        #expect(transcripts(state, ["/c/tts_a.mp3", "/c/tts_b.mp3", "/c/song.mp3"]).isEmpty)
        #expect(transcripts(state, ["/c/tts_a.mp3"]).isEmpty)
    }

    @Test func onlyTheReplysOwnTurnCounts() {
        let history = [
            HistoryMessage(role: "user", text: "Say hi"),
            HistoryMessage(role: "tool", name: "text_to_speech", toolCallId: "a", args: ["text": "Hi."]),
            HistoryMessage(role: "assistant", text: "MEDIA:/c/tts_a.mp3"),
            HistoryMessage(role: "user", text: "Send the song"),
            HistoryMessage(role: "assistant", text: "MEDIA:/c/song.mp3"),
        ]
        let state = ThreadState(history: history, running: false)

        #expect(transcripts(state, ["/c/song.mp3"]).isEmpty)
        #expect(
            SpokenAudio.transcripts(in: state.items, replyAt: 2, audioPaths: ["/c/tts_a.mp3"]) == [
                "/c/tts_a.mp3": "Hi."
            ])
    }

    @Test func aRequestedOutputPathMatchesThatFile() {
        let history = [
            HistoryMessage(role: "user", text: "Read it"),
            HistoryMessage(
                role: "tool", name: "text_to_speech", toolCallId: "a",
                args: ["text": "Chapter one.", "output_path": "/home/h/book/ch1.mp3"]),
            HistoryMessage(role: "assistant", text: "MEDIA:/home/h/intro.mp3\nMEDIA:/home/h/book/ch1.mp3"),
        ]
        let state = ThreadState(history: history, running: false)

        #expect(
            transcripts(state, ["/home/h/intro.mp3", "/home/h/book/ch1.mp3"]) == [
                "/home/h/book/ch1.mp3": "Chapter one."
            ])
    }

    @Test func failedCallsLeaveNoFiles() {
        var state = ThreadState()
        state.apply(event("message.start", [:]))
        state.apply(event("tool.start", ["tool_id": "t1", "name": "text_to_speech", "args": ["text": "Hi"]]))
        state.apply(event("tool.complete", ["tool_id": "t1", "result": ["error": "TTS dependency missing"]]))
        guard case .activity(let steps) = state.items.last?.content else {
            Issue.record("no activity")
            return
        }
        #expect(steps.first?.state == .failed)
        #expect(steps.first?.audioFiles == nil)
    }

    @Test func recognisesTheTTSToolsDefaultFileNames() {
        #expect(SpokenAudio.isSpeechFile("/home/h/.hermes/cache/audio/tts_20261102_071502_118204.mp3"))
        #expect(SpokenAudio.isSpeechFile("/root/.hermes/audio_cache/tts_20261102_071502.ogg"))
        #expect(!SpokenAudio.isSpeechFile("/home/h/music/tts_notes.mp3"))
        #expect(!SpokenAudio.isSpeechFile("/home/h/podcast.mp3"))
    }
}
