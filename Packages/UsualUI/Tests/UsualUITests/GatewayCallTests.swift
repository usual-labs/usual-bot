import Foundation
import HermesKit
import Testing

@testable import UsualUI

/// When a Gateway call hears you start and stop, and which engine a call runs on.
struct GatewayCallTests {
    /// Samples every 50 ms from `start`, at `level`, for `seconds`.
    private func feed(
        _ detector: inout TurnDetector, level: Double, from start: Double, for seconds: Double
    ) -> [TurnDetector.Event] {
        var events: [TurnDetector.Event] = []
        var time = start
        while time < start + seconds - 0.0001 {
            if let event = detector.heard(level, at: time) { events.append(event) }
            time += 0.05
        }
        return events
    }

    @Test func aTurnStartsWithYourVoiceAndEndsAfterAPause() {
        var detector = TurnDetector()
        #expect(feed(&detector, level: 0.1, from: 0, for: 1).isEmpty)
        #expect(feed(&detector, level: 0.7, from: 1, for: 1) == [.started])
        // A breath between words doesn't end it.
        #expect(feed(&detector, level: 0.1, from: 2, for: 0.5).isEmpty)
        #expect(feed(&detector, level: 0.7, from: 2.5, for: 0.5).isEmpty)
        #expect(feed(&detector, level: 0.1, from: 3, for: 1.5) == [.ended])
    }

    @Test func aClickIsNotATurn() {
        var detector = TurnDetector()
        #expect(feed(&detector, level: 0.9, from: 0, for: 0.1).isEmpty)
        #expect(feed(&detector, level: 0.1, from: 0.1, for: 2).isEmpty)
    }

    @Test func wordsFromTheGatewayKeepTheTurnOpen() {
        var detector = TurnDetector()
        _ = feed(&detector, level: 0.7, from: 0, for: 0.5)
        _ = feed(&detector, level: 0.1, from: 0.5, for: 1)
        detector.heardWords(at: 1.5)
        #expect(feed(&detector, level: 0.1, from: 1.5, for: 1).isEmpty)
        #expect(feed(&detector, level: 0.1, from: 2.5, for: 0.5) == [.ended])
    }

    @Test func cuttingInTakesLongerThanStarting() {
        var detector = TurnDetector()
        detector.startAfter = TurnDetector.bargeInAfter
        #expect(feed(&detector, level: 0.7, from: 0, for: 0.3).isEmpty)
        #expect(feed(&detector, level: 0.1, from: 0.3, for: 0.2).isEmpty)
        #expect(feed(&detector, level: 0.7, from: 0.5, for: 0.6) == [.started])
    }

    @Test func automaticKeepsChainedCallsOnTheDevice() {
        let chained = VoiceLiveStatus(mode: "chained", available: true)
        #expect(CallSettings.resolve(choice: "", status: chained) == .onDevice)
        #expect(CallSettings.resolve(choice: "", status: nil) == .onDevice)
    }

    @Test func gatewayIsUsedOnlyWhenChosen() {
        #expect(CallSettings.resolve(choice: "gateway", status: nil) == .gateway)
        #expect(
            CallSettings.resolve(choice: "gateway", status: VoiceLiveStatus(mode: "gpt-live", available: true))
                == .gateway)
        #expect(
            CallSettings.resolve(choice: "apple", status: VoiceLiveStatus(mode: "gpt-live", available: true))
                == .onDevice)
    }

    @Test func gptLiveResolvesAsBefore() {
        let live = VoiceLiveStatus(mode: "gpt-live", available: true)
        #expect(CallSettings.resolve(choice: "", status: live) == .gptLive)
        #expect(CallSettings.resolve(choice: "gpt-live", status: live) == .gptLive)
        #expect(
            CallSettings.resolve(choice: "", status: VoiceLiveStatus(mode: "gpt-live", available: false)) == .onDevice)
        guard
            case .unavailable(let problem) = CallSettings.resolve(
                choice: "gpt-live", status: VoiceLiveStatus(mode: "chained", available: false, reason: "no OpenAI key"))
        else {
            Issue.record("GPT-Live without a key should say why")
            return
        }
        #expect(problem.contains("no OpenAI key"))
    }

    @Test func aTurnUploadsAsAWAVFile() {
        let wav = TurnTap.wav(Data([1, 0, 2, 0]))
        #expect(wav.count == 48)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(wav.suffix(4) == Data([1, 0, 2, 0]))
    }
}
