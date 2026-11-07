import Foundation
import Testing

@testable import UsualUI

struct ConversationScrollTests {
    @Test func earlierMessagesAddedAboveKeepTheReaderOnTheSameMessage() {
        var state = ConversationScrollState()
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 4_300))
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 500))
        #expect(state.nearsTop)
        state.addingAbove()
        // Asked once: the next page waits for this one's layout.
        #expect(!state.nearsTop)
        // Still scrolling: the same message stays put, 3,000 points further down.
        #expect(state.update(.init(contentHeight: 8_000, height: 700, offset: 480)) == 3_480)
        #expect(state.update(.init(contentHeight: 8_000, height: 700, offset: 3_480)) == nil)
        #expect(!state.nearsTop)
    }

    @Test func aShortConversationFollowingTheEndFillsUpWithEarlierMessages() {
        var state = ConversationScrollState()
        _ = state.update(.init(contentHeight: 1_000, height: 700, offset: 300))
        #expect(state.nearsTop)
        state.addingAbove()
        // Following the end, the end is where it goes.
        #expect(state.update(.init(contentHeight: 4_000, height: 700, offset: 300)) == 3_300)
        _ = state.update(.init(contentHeight: 4_000, height: 700, offset: 3_300))
        #expect(!state.nearsTop)
    }

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

    @Test func theWayBackShowsOnlyAwayFromTheEndAndNotesWhatArrived() {
        var state = ConversationScrollState()
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 4_300))
        state.arrived(atReload: 0)
        #expect(!state.isAwayFromEnd)
        #expect(!state.hasNewBelow)
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 1_500))
        _ = state.scrollingByHand(false)
        #expect(state.isAwayFromEnd)
        state.arrived(atReload: 0)
        #expect(state.hasNewBelow)
        // Taking the way back follows the end again and forgets what was new.
        #expect(state.jumpToEnd() == 4_300)
        #expect(state.followsEnd)
        #expect(!state.hasNewBelow)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 4_300))
        #expect(!state.isAwayFromEnd)
    }

    @Test func scrollingBackDownByHandHidesTheWayBack() {
        var state = ConversationScrollState()
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 1_500))
        _ = state.scrollingByHand(false)
        state.arrived(atReload: 0)
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 4_280))
        _ = state.scrollingByHand(false)
        #expect(state.followsEnd)
        #expect(!state.isAwayFromEnd)
        #expect(!state.hasNewBelow)
    }

    @Test func aMessageFoundBySearchOffersTheWayBack() {
        var state = ConversationScrollState()
        state.leaveEnd(atReload: 0)
        _ = state.update(.init(contentHeight: 50_000, height: 700, offset: 1_200))
        #expect(state.isAwayFromEnd)
    }

    @Test func historyLoadedForASearchResultIsntNewBelow() {
        var state = ConversationScrollState()
        state.arrived(atReload: 0)
        state.leaveEnd(atReload: 1)
        _ = state.update(.init(contentHeight: 50_000, height: 700, offset: 1_200))
        // The longer transcript comes with the load, before or after the jump.
        state.arrived(atReload: 1)
        #expect(!state.hasNewBelow)
        state.arrived(atReload: 1)
        #expect(state.hasNewBelow)
    }

    @Test func sendingBringsTheEndBackWhereverYouHadScrolled() {
        var state = ConversationScrollState()
        #expect(state.sent(.init(load: 1, count: 3)) == nil)
        _ = state.scrollingByHand(true)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 1_500))
        _ = state.scrollingByHand(false)
        #expect(!state.followsEnd)
        #expect(state.sent(.init(load: 1, count: 4)) == 4_300)
        #expect(state.followsEnd)
    }

    @Test func aReloadOrAnUndoIsntSending() {
        var state = ConversationScrollState()
        _ = state.sent(.init(load: 1, count: 3))
        state.leaveEnd(atReload: 2)
        _ = state.update(.init(contentHeight: 50_000, height: 700, offset: 1_200))
        // History loaded for a search result holds more of your messages; the result stays put.
        #expect(state.sent(.init(load: 2, count: 40)) == nil)
        #expect(state.sent(.init(load: 2, count: 39)) == nil)
        #expect(!state.followsEnd)
    }
}

struct KeptSpaceTests {
    @Test func theSpaceKeptAtTheEndGoesOnlyOnceItIsOutOfSight() {
        var state = ConversationScrollState()
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 4_300))
        let start = state.releases
        _ = state.scrollingByHand(true)
        // Just above the end, the space may still show.
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 4_100))
        #expect(state.releases == start)
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 3_000))
        #expect(state.releases == start + 1)
        // Once, not on every frame of the scroll.
        _ = state.update(.init(contentHeight: 5_000, height: 700, offset: 2_000))
        #expect(state.releases == start + 1)
    }

    @Test func aReloadOrAnUndoLetsTheSpaceGo() {
        var state = ConversationScrollState()
        _ = state.sent(SentMessages(load: 1, count: 3))
        let start = state.releases
        _ = state.sent(SentMessages(load: 1, count: 4))
        #expect(state.releases == start)
        _ = state.sent(SentMessages(load: 1, count: 3))
        #expect(state.releases == start + 1)
        _ = state.reload(2)
        #expect(state.releases == start + 2)
    }
}

#if os(macOS)
    import AppKit
    import SwiftUI

    @MainActor
    struct GrowsOnlyTests {
        @Observable final class Rows {
            var height: CGFloat = 500
            var release = 0
        }

        struct Column: View {
            let rows: Rows
            var body: some View {
                GrowsOnly(release: rows.release) { Color.clear.frame(height: rows.height) }
                    .frame(width: 300)
            }
        }

        private func height(_ view: NSHostingView<Column>) -> CGFloat {
            view.layoutSubtreeIfNeeded()
            return view.fittingSize.height
        }

        @Test func whatLeavesTheEndLeavesItsSpaceUntilItIsLetGo() {
            let rows = Rows()
            let view = NSHostingView(rootView: Column(rows: rows))
            view.frame = CGRect(x: 0, y: 0, width: 300, height: 800)
            #expect(height(view) == 500)
            rows.height = 400
            #expect(height(view) == 500)
            // What arrives fills the space first.
            rows.height = 450
            #expect(height(view) == 500)
            rows.height = 600
            #expect(height(view) == 600)
            // More than the limit goes, as an undo can.
            rows.height = 100
            #expect(height(view) == 100 + GrowsOnly.limit)
            rows.release += 1
            #expect(height(view) == 100)
        }
    }
#endif
