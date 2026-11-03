import Foundation
import Testing

@testable import HermesKit

/// What a chat's row says and when it was last active, between roster refreshes.
@MainActor
struct SidebarPreviewTests {
    private let rosterTime = Date(timeIntervalSince1970: 1_700_000_000)

    private func model(history: [HistoryMessage]) -> AppModel {
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        model.contacts = [Contact(id: "atlas", name: "Atlas", preview: "From the roster", lastActive: rosterTime)]
        model.threads["atlas"] = ChatThread.sample("atlas", state: ThreadState(history: history, running: false))
        return model
    }

    private func message(_ role: String, _ text: String, minutesAfterRoster minutes: Double) -> HistoryMessage {
        HistoryMessage(
            role: role, text: text, timestamp: rosterTime.addingTimeInterval(minutes * 60).timeIntervalSince1970)
    }

    @Test func aChatShowsWhatYouSentUntilTheRosterCatchesUp() throws {
        let model = model(history: [message("assistant", "An older reply", minutesAfterRoster: -5)])
        #expect(model.sidebarContacts.first?.preview == "From the roster")
        #expect(model.sidebarContacts.first?.lastActive == rosterTime)

        model.threads["atlas"]?.state.sendLocally("Book the café for Friday")
        let row = try #require(model.sidebarContacts.first)
        #expect(row.preview == "Book the café for Friday")
        #expect(try #require(row.lastActive) > rosterTime)
    }

    @Test func aReplyNewerThanTheRosterBecomesThePreviewAsPlainText() {
        let model = model(history: [
            message("user", "Is it booked?", minutesAfterRoster: 1),
            message("assistant", "**Done**: the café is booked.\nMEDIA:/tmp/receipt.png", minutesAfterRoster: 2),
            HistoryMessage(
                role: "tool", name: "terminal", context: "ls", timestamp: rosterTime.timeIntervalSince1970 + 180),
        ])
        let row = model.sidebarContacts.first
        #expect(row?.preview == "Done: the café is booked.")
        #expect(row?.lastActive == rosterTime.addingTimeInterval(120))
    }

    @Test func theRosterWinsWhenItHeardOfSomethingNewer() {
        // Another device chatted since this one loaded the chat.
        let model = model(history: [message("assistant", "Old news", minutesAfterRoster: -1)])
        #expect(model.sidebarContacts.first?.preview == "From the roster")
        #expect(model.sidebarContacts.first?.lastActive == rosterTime)
    }
}
