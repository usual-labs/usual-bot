import Foundation
import Observation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
struct NewLineTests {
    private func item(_ id: Int, _ content: TranscriptItem.Content, at seconds: TimeInterval) -> TranscriptItem {
        TranscriptItem(id: id, content: content, date: Date(timeIntervalSince1970: seconds))
    }

    private var items: [TranscriptItem] {
        [
            item(0, .assistant("Old"), at: 900),
            item(1, .user("Question"), at: 1_100),
            item(2, .assistant("New 1"), at: 1_200),
            item(3, .assistant("New 2"), at: 1_300),
        ]
    }

    /// The same messages as the gateway sends them, numbered 0 to 3.
    private var history: ThreadState {
        ThreadState(
            history: [
                HistoryMessage(role: "assistant", text: "Old", timestamp: 900),
                HistoryMessage(role: "user", text: "Question", timestamp: 1_100),
                HistoryMessage(role: "assistant", text: "New 1", timestamp: 1_200),
                HistoryMessage(role: "assistant", text: "New 2", timestamp: 1_300),
            ], running: false)
    }

    @Test func goesAboveTheFirstReplyAfterYouLastLooked() {
        let line = NewLine.unread(count: 2, since: Date(timeIntervalSince1970: 1_000))
        #expect(line?.itemID(in: items) == 2)
    }

    @Test func withoutAReadTimeCountsBackFromTheNewest() {
        #expect(NewLine.unread(count: 1, since: nil)?.itemID(in: items) == 3)
        #expect(NewLine.unread(count: 9, since: nil)?.itemID(in: items) == 0)
    }

    @Test func nothingUnreadHasNoLine() {
        #expect(NewLine.unread(count: 0, since: .now) == nil)
    }

    @Test func comingOnScreenKeepsTheLineWhileYouRead() {
        let thread = ChatThread.sample("atlas", state: history)
        thread.lastViewed = Date(timeIntervalSince1970: 1_000)
        thread.unreadCount = 2

        thread.isVisible = true
        #expect(thread.unreadCount == 0)
        #expect(thread.newLine?.itemID(in: thread.state.items) == 2)
        // Still on screen: the line stays where it was.
        thread.isVisible = true
        #expect(thread.newLine?.itemID(in: thread.state.items) == 2)

        _ = thread.opened()
        #expect(thread.newLine?.itemID(in: thread.state.items) == 2)

        // The window went behind another and came back, nothing new meanwhile: the line stays.
        thread.isVisible = false
        thread.isVisible = true
        #expect(thread.newLine?.itemID(in: thread.state.items) == 2)

        // Opened again later with nothing new: no line.
        thread.isVisible = false
        thread.isVisible = true
        _ = thread.opened()
        #expect(thread.newLine == nil)
    }

    @Test func openingAChatWithNoLineDoesNotRedrawIt() {
        let thread = ChatThread.sample("atlas", state: history)
        thread.isVisible = true
        _ = thread.opened()
        // A chat kept built out of sight is opened each time it's shown again; with no line to
        // move, nothing that draws it may change.
        let redrawn = Mutex(false)
        withObservationTracking {
            _ = thread.newLine
        } onChange: {
            redrawn.withLock { $0 = true }
        }
        thread.isVisible = false
        thread.isVisible = true
        _ = thread.opened()
        #expect(thread.newLine == nil)
        #expect(!redrawn.withLock { $0 })
    }

    @Test func aLineMovedByNewRepliesStillGoesOnTheNextOpening() {
        let thread = ChatThread.sample("atlas", state: history)
        thread.lastViewed = Date(timeIntervalSince1970: 1_250)
        thread.unreadCount = 1
        thread.isVisible = true
        _ = thread.opened()
        // Back to the window with a reply unread, then to another chat and back with none.
        thread.isVisible = false
        thread.unreadCount = 1
        thread.isVisible = true
        thread.isVisible = false
        thread.isVisible = true
        _ = thread.opened()
        #expect(thread.newLine == nil)
    }

    @Test func openingBeforeComingOnScreenStillPlacesIt() {
        let thread = ChatThread.sample("atlas", state: history)
        thread.lastViewed = Date(timeIntervalSince1970: 1_000)
        thread.unreadCount = 2
        _ = thread.opened()
        thread.isVisible = true
        #expect(thread.newLine?.itemID(in: thread.state.items) == 2)
    }

    @Test func markedUnreadFromAMessageGoesAboveIt() {
        let thread = ChatThread.sample("atlas", state: history)
        thread.isVisible = true
        thread.markUnread(from: thread.state.items[1])
        thread.isVisible = false

        thread.isVisible = true
        _ = thread.opened()
        #expect(thread.newLine?.itemID(in: thread.state.items) == 1)
    }
}
