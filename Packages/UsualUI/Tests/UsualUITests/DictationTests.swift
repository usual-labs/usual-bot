import AVFoundation
import Testing

@testable import UsualUI

struct DictationTests {
    @Test func spokenWordsFollowWhatWasTyped() {
        #expect(Dictation.merge("", "Ship it") == "Ship it")
        #expect(Dictation.merge("/web-research", "Qdrant pricing") == "/web-research Qdrant pricing")
        #expect(Dictation.merge("@atlas ", "check this") == "@atlas check this")
        #expect(Dictation.merge("Draft", "") == "Draft")
    }

    @Test func gatewayWordsReplaceTheLiveOnes() {
        // The box shows "Note: check the" from the stream; the final words take their place.
        #expect(
            GatewayJob.placing("check the backups", prefix: "Note:", now: "Note: check the", sawPartial: true)
                == "Note: check the backups")
    }

    @Test func gatewayWordsWithoutLiveOnesFollowWhatsInTheBoxNow() {
        // Typed while the recording was being transcribed: kept, and the words go after it.
        #expect(
            GatewayJob.placing("check the backups", prefix: "Note:", now: "Note: urgent", sawPartial: false)
                == "Note: urgent check the backups")
    }

    @Test func hearingNothingLeavesTheBoxAlone() {
        #expect(GatewayJob.placing("", prefix: "Note:", now: "Note: urgent", sawPartial: false) == nil)
    }

    @Test func theStreamGetsSixteenBitLittleEndianSamples() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let samples = try #require(buffer.floatChannelData?[0])
        // Loud enough to clip is clipped, not wrapped around.
        for (index, value) in [Float(0), 0.5, -1, 2].enumerated() { samples[index] = value }
        let pcm = [UInt8](GatewayRecording.pcm16(buffer))
        #expect(pcm == [0x00, 0x00, 0xFF, 0x3F, 0x01, 0x80, 0xFF, 0x7F])
    }
}
