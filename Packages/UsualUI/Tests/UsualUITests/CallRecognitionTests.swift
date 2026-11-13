import Foundation
import Testing

@testable import UsualUI

/// What a call does when its speech recognition ends. A recognizer that fails as it starts used to
/// be restarted at once, hundreds of times a second, while the call bar sat silent.
struct CallRecognitionTests {
    private let failedToStart = NSError(domain: "kLSRErrorDomain", code: 300)

    @Test func listensAgainAfterAFinalResultOrSilence() {
        #expect(VoiceCall.afterRecognition(error: nil, heardWords: true, onDevice: true) == .listenAgain)
        let silence = NSError(domain: "kAFAssistantErrorDomain", code: 1110)
        #expect(VoiceCall.afterRecognition(error: silence, heardWords: false, onDevice: true) == .listenAgain)
    }

    @Test func triesApplesServersWhenOnDeviceRecognitionCantStart() {
        #expect(VoiceCall.afterRecognition(error: failedToStart, heardWords: false, onDevice: true) == .useServer)
    }

    @Test func endsTheCallWhenRecognitionKeepsFailing() {
        guard case .fail = VoiceCall.afterRecognition(error: failedToStart, heardWords: false, onDevice: false) else {
            Issue.record("A recognizer that can't start should end the call with a message")
            return
        }
    }

    @Test func listensAgainWhenAnErrorFollowsWords() {
        #expect(VoiceCall.afterRecognition(error: failedToStart, heardWords: true, onDevice: false) == .listenAgain)
    }
}
