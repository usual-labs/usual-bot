import Foundation
import Testing

@testable import UsualUI

@MainActor
struct ReadAloudTests {
    /// Stands in for the device's voice: keeps what it was asked to say, and says nothing.
    final class SilentVoice: ReadingVoice {
        var said: [String] = []
        var stops = 0
        var finished: (@MainActor () -> Void)?

        func speak(_ sentences: [String], finished: @escaping @MainActor () -> Void) {
            said = sentences
            self.finished = finished
        }

        func stop() {
            stops += 1
            finished = nil
        }
    }

    private let playback = MediaPlayback()
    private let voice = SilentVoice()
    private var reading: ReadAloud { ReadAloud(playback: playback, voice: voice) }

    @Test func readsTheWordsAndSaysWhichMessage() {
        let reading = reading
        let key = ReadAloud.key(scope: "window", chat: "ops", item: 4)
        reading.read("## Done\nPushed **it**.\n```\ncode\n```", key: key)
        #expect(voice.said == ["Done", "Pushed it."])
        #expect(reading.key == key)
        voice.finished?()
        #expect(reading.key == nil)
    }

    @Test func aSecondMessageReplacesTheFirst() {
        let reading = reading
        reading.read("One.", key: "a")
        let first = voice.finished
        reading.read("Two.", key: "b")
        #expect(voice.said == ["Two."])
        // The first reading ending late doesn't end the second.
        first?()
        #expect(reading.key == "b")
        reading.stop()
        #expect(reading.key == nil)
        #expect(voice.finished == nil)
    }

    @Test func nothingToSayReadsNothing() {
        let reading = reading
        reading.read("MEDIA:/tmp/a.mp3", key: "a")
        #expect(reading.key == nil)
        #expect(voice.said.isEmpty)
    }

    @Test func aVoiceMemoStartingStopsTheReading() {
        let reading = reading
        reading.read("One.", key: "a")
        playback.play(URL(filePath: "/dev/null"), key: MediaPlayback.key(scope: "window", profile: nil, path: "/a.mp3"))
        #expect(reading.key == nil)
        #expect(voice.stops == 1)
    }

    @Test func readingPausesWhatPlays() {
        let reading = reading
        playback.play(URL(filePath: "/dev/null"), key: "memo")
        reading.read("One.", key: "a")
        #expect(playback.player.rate == 0)
        #expect(reading.key == "a")
    }

    @Test func leavingOnePlaceStopsOnlyWhatIsReadThere() {
        let reading = reading
        reading.read("One.", key: ReadAloud.key(scope: "panel", chat: "ops", item: 1))
        playback.stop(in: "window")
        #expect(reading.key != nil)
        playback.stop(in: "panel")
        #expect(reading.key == nil)
    }

    @Test func nothingIsReadDuringACall() {
        let reading = reading
        reading.read("One.", key: "a")
        reading.callStarted()
        #expect(reading.key == nil)
        reading.read("Two.", key: "b")
        #expect(reading.key == nil)
        reading.callEnded()
        reading.read("Two.", key: "b")
        #expect(reading.key == "b")
    }
}
