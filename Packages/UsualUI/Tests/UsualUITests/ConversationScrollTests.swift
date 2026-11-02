import Foundation
import Testing

@testable import UsualUI

struct ConversationScrollTests {
    @Test func aLateLayoutChangeCannotLeaveTheViewportBeyondTheMessages() {
        var state = ConversationScrollState()
        _ = state.update(.init(contentHeight: 10_000, height: 700, offset: 9_300))
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 10_000, height: 700, offset: 8_000))
        _ = state.scrollingByHand(false)
        #expect(!state.followsEnd)
        // A shorter reload, rewrap or folded card must not leave a screen of blank space.
        #expect(state.update(.init(contentHeight: 5_000, height: 700, offset: 8_000)) == 4_300)
    }

    @Test func returningFromAnotherAppEndsAnInterruptedGestureAndRepairsBlankSpace() {
        var state = ConversationScrollState()
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 8_000))
        #expect(state.resume() == 4_300)
        #expect(!state.isScrollingByHand)
    }

    @Test func readingOlderMessagesSurvivesNewRepliesAndReturningToTheApp() {
        var state = ConversationScrollState()
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 1_500))
        _ = state.scrollingByHand(false)
        #expect(state.update(.init(contentHeight: 6_000, height: 700, offset: 1_500)) == nil)
        #expect(state.resume() == nil)
        #expect(!state.followsEnd)
    }

    @Test func followingTheEndHandlesGrowthAndChangesToTheMessageBox() {
        var state = ConversationScrollState()
        #expect(state.update(.init(contentHeight: 400, height: 700, offset: 0)) == nil)
        #expect(state.update(.init(contentHeight: 900, height: 700, offset: 0)) == 200)
        #expect(state.update(.init(contentHeight: 900, height: 500, offset: 200)) == 400)
        #expect(state.update(.init(contentHeight: 900, height: 500, offset: 400)) == nil)
    }

    @Test func draggingAndRubberBandingAreLeftAloneUntilTheGestureEnds() {
        var state = ConversationScrollState()
        _ = state.scrollingByHand(true)
        #expect(state.update(.init(contentHeight: 5_000, height: 700, offset: 4_500)) == nil)
        #expect(state.scrollingByHand(false) == 4_300)
        #expect(state.followsEnd)
        _ = state.scrollingByHand(true)
        #expect(state.update(.init(contentHeight: 5_000, height: 700, offset: -60)) == nil)
        #expect(state.scrollingByHand(false) == 0)
        #expect(!state.followsEnd)
    }

    @Test func reloadingUsesTheNewLayoutAndIgnoresAnUnmeasuredViewport() {
        var state = ConversationScrollState()
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 1_500))
        _ = state.scrollingByHand(false)
        #expect(state.reload(1) == 4_300)
        #expect(state.update(.init(contentHeight: 8_000, height: 700, offset: 4_300)) == 7_300)
        #expect(state.update(.init(contentHeight: 0, height: 0, offset: 0)) == nil)
        #expect(state.viewport?.end == 7_300)
    }

    @Test func aMessageFoundBySearchStaysOnScreenWhenRepliesArrive() {
        var state = ConversationScrollState()
        state.leaveEnd(atReload: 0)
        // The first layout of a chat opened from search, then the jump to a message far up.
        #expect(state.update(.init(contentHeight: 50_000, height: 700, offset: 49_300)) == nil)
        #expect(state.update(.init(contentHeight: 50_000, height: 700, offset: 1_200)) == nil)
        #expect(state.update(.init(contentHeight: 50_400, height: 700, offset: 1_200)) == nil)
        #expect(!state.followsEnd)
    }

    @Test func aMessageFoundInHistoryJustLoadedIsntLostToTheReload() {
        var state = ConversationScrollState()
        _ = state.update(.init(contentHeight: 900, height: 700, offset: 200))
        // The history and the jump into it change together, and either handler may run first.
        state.leaveEnd(atReload: 1)
        #expect(state.reload(1) == nil)
        #expect(!state.followsEnd)
        #expect(state.update(.init(contentHeight: 6_000, height: 700, offset: 1_200)) == nil)
        // A later reload, such as reconnecting, opens at the newest message again.
        #expect(state.reload(2) == 5_300)
        #expect(state.followsEnd)
    }
}
