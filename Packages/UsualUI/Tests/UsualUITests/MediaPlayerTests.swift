import AVFoundation
import Foundation
import Testing

@testable import HermesKit
@testable import UsualUI

struct MediaPlayerTests {
    @Test func picksAPlayerByFileType() {
        #expect(MediaLoading.kind(of: "/c/audio/tts_20261102_071502_118204.MP3") == .audio)
        #expect(MediaLoading.kind(of: "/c/clip.mov") == .video)
        #expect(MediaLoading.kind(of: "/c/chart.png") == .image)
        #expect(MediaLoading.kind(of: "/c/report.pdf") == .file)
        #expect(MediaLoading.kind(of: "/c/README") == .file)
    }

    @Test func aRepliesVoiceMemoGetsTheTextItsCallSpoke() {
        let history = [
            HistoryMessage(role: "user", text: "Read it to me"),
            HistoryMessage(role: "tool", name: "text_to_speech", toolCallId: "a", args: ["text": "All clear."]),
            HistoryMessage(
                role: "assistant",
                text: "Here.\n[[audio_as_voice]]\nMEDIA:/c/tts_1.ogg\nMEDIA:/c/chart.png\nMEDIA:/c/clip.mp4"),
        ]
        let items = ThreadState(history: history, running: false).items

        #expect(TranscriptView.spokenTexts(in: items, at: 2) == ["/c/tts_1.ogg": "All clear."])
        #expect(TranscriptView.spokenTexts(in: items, at: 0).isEmpty)
    }

    @Test func timesReadLikeAClock() {
        #expect(PlayableText.time(7.9) == "0:07")
        #expect(PlayableText.time(754) == "12:34")
        #expect(PlayableText.time(3723) == "1:02:03")
    }

    @Test func aWaveformFollowsHowLoudTheAudioIs() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "waveform-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        // One second of silence, then one second of a tone.
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<16000 { samples[index] = index < 8000 ? 0 : 0.5 * sin(Float(index) / 4) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }

        let summary = try #require(await AudioSummary.make(url))
        #expect(abs(summary.duration - 2) < 0.01)
        #expect(summary.levels.count == 64)
        #expect(summary.levels.prefix(30).allSatisfy { $0 == 0 })
        #expect(summary.levels.suffix(30).allSatisfy { $0 > 0.9 })
    }

    @Test func aFileThatIsNotAudioIsUnplayable() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "not-audio-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not audio at all".utf8).write(to: url)
        #expect(await AudioSummary.make(url) == nil)
    }

    @MainActor @Test func leavingOnePlaceStopsOnlyWhatPlaysThere() {
        let playback = MediaPlayback()
        let url = URL(filePath: "/dev/null")
        playback.play(url, key: MediaPlayback.key(scope: "panel", profile: "ops", path: "/a.mp3"))
        playback.stop(in: "window")
        #expect(playback.key != nil)
        playback.stop(in: "panel")
        #expect(playback.key == nil)
    }
}
