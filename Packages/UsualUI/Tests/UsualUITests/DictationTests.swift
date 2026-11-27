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

    @Test func wordsAfterAPauseFollowTheEarlierOnes() {
        // Apple's recognizer closes an utterance at a pause, then reports only the next one.
        var spoken = Utterances()
        _ = spoken.adding("To be", endsUtterance: false)
        _ = spoken.adding("To be or not to be", endsUtterance: true)
        #expect(spoken.adding("I'm", endsUtterance: false) == "To be or not to be I'm")
        #expect(
            spoken.adding("I'm talking after a while", endsUtterance: true)
                == "To be or not to be I'm talking after a while")
        // The final result repeats the last utterance.
        #expect(
            spoken.adding("I'm talking after a while", endsUtterance: false)
                == "To be or not to be I'm talking after a while")
    }

    @Test func revisionsReplaceTheCurrentUtterance() {
        var spoken = Utterances()
        _ = spoken.adding("Two be or", endsUtterance: false)
        #expect(spoken.adding("To be or not", endsUtterance: false) == "To be or not")
        #expect(spoken.adding("", endsUtterance: false) == "To be or not")
    }

    @Test func aNewUtteranceIsKeptWhenThePauseWasntReported() {
        var spoken = Utterances()
        _ = spoken.adding("I'm talking after a while", endsUtterance: false)
        #expect(spoken.adding("Just", endsUtterance: false) == "I'm talking after a while Just")
    }

    @Test func gatewayWordsReplaceTheLiveOnes() {
        // The box shows "Note: check the" from the stream; the final words take their place.
        #expect(
            GatewayJob.placing(
                "check the backups", prefix: "Note:", now: "Note: check the", shown: "Note: check the")
                == "Note: check the backups")
    }

    @Test func typingAfterTheLiveWordsStaysAfterThem() {
        #expect(
            GatewayJob.placing(
                "check the backups", prefix: "Note:", now: "Note: check the, thanks", shown: "Note: check the")
                == "Note: check the backups, thanks")
    }

    @Test func anEditAmongTheLiveWordsKeepsTheBox() {
        // Changed within them, or a word made longer: there's no telling where the final words go.
        #expect(
            GatewayJob.placing("check the backups", prefix: "Note:", now: "Note: chuck the", shown: "Note: check the")
                == nil)
        #expect(
            GatewayJob.placing("check the backups", prefix: "Note:", now: "Note: check them", shown: "Note: check the")
                == nil)
    }

    @Test func liveWordsStopWritingOnceYouType() {
        #expect(GatewayJob.showing("check", prefix: "Note:", now: "Note:", shown: nil) == "Note: check")
        #expect(
            GatewayJob.showing("check the", prefix: "Note:", now: "Note: check", shown: "Note: check")
                == "Note: check the")
        // Typed after the live words, or before any came: they'd write over it.
        #expect(
            GatewayJob.showing("check the", prefix: "Note:", now: "Note: check, thanks", shown: "Note: check") == nil)
        #expect(GatewayJob.showing("check", prefix: "Note:", now: "Note: urgent", shown: nil) == nil)
    }

    @Test func gatewayWordsWithoutLiveOnesFollowWhatsInTheBoxNow() {
        // Typed while the recording was being transcribed: kept, and the words go after it.
        #expect(
            GatewayJob.placing("check the backups", prefix: "Note:", now: "Note: urgent", shown: nil)
                == "Note: urgent check the backups")
    }

    @Test func hearingNothingLeavesTheBoxAlone() {
        #expect(GatewayJob.placing("", prefix: "Note:", now: "Note: urgent", shown: nil) == nil)
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
