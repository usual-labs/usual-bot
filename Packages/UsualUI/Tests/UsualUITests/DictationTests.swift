import Testing

@testable import UsualUI

struct DictationTests {
    @Test func spokenWordsFollowWhatWasTyped() {
        #expect(Dictation.merge("", "Ship it") == "Ship it")
        #expect(Dictation.merge("/web-research", "Qdrant pricing") == "/web-research Qdrant pricing")
        #expect(Dictation.merge("@atlas ", "check this") == "@atlas check this")
        #expect(Dictation.merge("Draft", "") == "Draft")
    }
}
