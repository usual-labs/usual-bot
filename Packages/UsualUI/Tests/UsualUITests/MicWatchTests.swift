import Testing

@testable import UsualUI

/// A call notices its microphone stopping under it, starts it again, and gives up only when that
/// keeps failing.
struct MicWatchTests {
    @Test func aMicrophoneThatKeepsHearingIsLeftAlone() {
        var watch = MicWatch(at: 0)
        for tick in 1...100 {
            let time = Double(tick) * 0.05
            watch.heardBuffer(at: time)
            #expect(watch.check(running: true, at: time) == .fine)
        }
    }

    @Test func aStoppedEngineIsStartedAgainAtOnce() {
        var watch = MicWatch(at: 0)
        watch.heardBuffer(at: 1)
        #expect(watch.check(running: false, at: 1.05) == .restart)
    }

    @Test func aMicrophoneThatGoesQuietIsStartedAgain() {
        // The engine can say it's running while the tap gets nothing.
        var watch = MicWatch(at: 0)
        watch.heardBuffer(at: 1)
        #expect(watch.check(running: true, at: 1.5) == .fine)
        #expect(watch.check(running: true, at: 2.1) == .restart)
        // It gets a moment to come back before the next try.
        #expect(watch.check(running: true, at: 2.5) == .fine)
        watch.heardBuffer(at: 2.6)
        #expect(watch.check(running: true, at: 3) == .fine)
    }

    @Test func itGivesUpWhenStartingAgainKeepsFailing() {
        var watch = MicWatch(at: 0)
        var actions: [MicWatch.Action] = []
        var time = 0.0
        while time < 10 {
            time += 0.05
            let action = watch.check(running: false, at: time)
            if action != .fine { actions.append(action) }
            if action == .giveUp { break }
        }
        #expect(actions == [.restart, .restart, .restart, .giveUp])
    }

    @Test func hearingAgainForgivesEarlierRestarts() {
        var watch = MicWatch(at: 0)
        #expect(watch.check(running: false, at: 0.1) == .restart)
        #expect(watch.check(running: false, at: 1.2) == .restart)
        watch.heardBuffer(at: 1.3)
        #expect(watch.check(running: false, at: 1.4) == .restart)
        #expect(watch.check(running: false, at: 2.5) == .restart)
        #expect(watch.check(running: false, at: 3.6) == .restart)
    }
}
