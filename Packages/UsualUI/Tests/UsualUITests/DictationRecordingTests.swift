import Testing

@testable import UsualUI

/// On-device dictation against a fake recognizer. Apple's recognizer still reports its final words
/// after it's told to stop, so these check where words that arrive late go.
@MainActor
struct DictationRecordingTests {
    @Test func wordsAfterSendingStayOutOfTheBox() async {
        let box = Box()
        let dictation = Dictation()
        let recognizer = FakeRecognizer()
        await dictation.listen(into: box, with: recognizer)
        recognizer.hears("Ship it")
        #expect(box.text == "Ship it")
        // Send stops dictation and empties the box; the recognizer's final words come after.
        dictation.stop()
        box.text = ""
        recognizer.ends(with: "Ship it.")
        #expect(box.text == "")
    }

    @Test func theFinalWordsCorrectABoxLeftAsItWas() async {
        let box = Box(text: "Note:")
        let dictation = Dictation()
        let recognizer = FakeRecognizer()
        await dictation.listen(into: box, with: recognizer)
        recognizer.hears("check the backup")
        dictation.stop()
        recognizer.ends(with: "check the backups.")
        #expect(box.text == "Note: check the backups.")
    }

    @Test func typingAfterStoppingIsKept() async {
        let box = Box()
        let dictation = Dictation()
        let recognizer = FakeRecognizer()
        await dictation.listen(into: box, with: recognizer)
        recognizer.hears("Ship it")
        dictation.stop()
        box.text = "Ship it now"
        recognizer.ends(with: "Ship it.")
        #expect(box.text == "Ship it now")
    }

    @Test func cancellingTakesTheWordsBackOut() async {
        let box = Box(text: "Note:")
        let dictation = Dictation()
        let recognizer = FakeRecognizer()
        await dictation.listen(into: box, with: recognizer)
        recognizer.hears("check this")
        dictation.cancel()
        #expect(box.text == "Note:")
        recognizer.ends(with: "check this.")
        #expect(box.text == "Note:")
        #expect(dictation.state == .idle)
    }

    @Test func sendingWithFilesKeepsTheBoxAsItWasSent() async {
        // With files the box keeps its text until they're up, then empties only if it's unchanged.
        let box = Box()
        let dictation = Dictation()
        let recognizer = FakeRecognizer()
        await dictation.listen(into: box, with: recognizer)
        recognizer.hears("Here's the log")
        dictation.stop(keepingLateWords: false)
        recognizer.ends(with: "Here's the log.")
        #expect(box.text == "Here's the log")
    }

    @Test func aStoppedRecordingLeavesTheNextOneAlone() async {
        let box = Box()
        let dictation = Dictation()
        let first = FakeRecognizer()
        await dictation.listen(into: box, with: first)
        first.hears("One")
        dictation.stop()
        let second = FakeRecognizer()
        await dictation.listen(into: box, with: second)
        second.hears("two")
        // The first recording's final words and its end arrive during the second.
        first.ends(with: "One.")
        #expect(box.text == "One two")
        #expect(dictation.state == .listening)
        second.hears("two three")
        #expect(box.text == "One two three")
    }
}

struct DictationWaveformTests {
    @Test func quietFillsTheLeftUntilEnoughIsHeard() {
        #expect(DictationWaveform.bars([0.5, 0.8], count: 4) == [0, 0, 0.5, 0.8])
    }

    @Test func theNewestBarsShow() {
        #expect(DictationWaveform.bars([0.1, 0.2, 0.3, 0.4], count: 2) == [0.3, 0.4])
        #expect(DictationWaveform.bars([0.1], count: 0) == [])
    }
}

/// The message box's text.
@MainActor
private final class Box {
    var text: String
    init(text: String = "") { self.text = text }
}

/// Reports what a test says it heard, as Apple's recognizer reports results.
@MainActor
private final class FakeRecognizer: SpeechRecording {
    private var callbacks: SpeechCallbacks?

    func start(_ callbacks: SpeechCallbacks) -> FakeRecognizer {
        self.callbacks = callbacks
        return self
    }

    nonisolated func stop() {}

    func hears(_ words: String) {
        callbacks?.onText(words, false)
    }

    /// The final result, then the end, as Apple's recognizer sends them after `stop`.
    func ends(with words: String) {
        callbacks?.onText(words, false)
        callbacks?.onEnd(nil)
    }
}

extension Dictation {
    /// Starts On-device dictation into `box`, with `recognizer` in place of Apple's.
    fileprivate func listen(into box: Box, with recognizer: FakeRecognizer) async {
        permission = { nil }
        self.recognizer = { recognizer.start($0) }
        await start(after: box.text, current: { box.text }, update: { box.text = $0 })?.value
    }
}
