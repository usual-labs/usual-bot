import Foundation
import Testing

@testable import HermesKit

/// The number on the app's icon.
@MainActor
struct AppBadgeTests {
    private func model() -> AppModel {
        AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
    }

    @Test func itAddsUpEveryChatsUnreadReplies() {
        let model = model()
        model.contacts = [
            Contact(id: "atlas", name: "Atlas"), Contact(id: "forge", name: "Forge"),
            Contact(id: "sage", name: "Sage", unreadCount: 4),
        ]
        model.threads["atlas"] = ChatThread.sample("atlas", state: ThreadState(history: [], running: false))
        model.threads["forge"] = ChatThread.sample("forge", state: ThreadState(history: [], running: false))
        model.threads["atlas"]?.unreadCount = 2
        model.threads["forge"]?.unreadCount = 1
        // A chat not loaded yet counts what the roster says.
        #expect(model.badgeCount == 7)

        model.threads["atlas"]?.unreadCount = 0
        #expect(model.badgeCount == 5)
    }

    @Test func aChatNoLongerListedDoesntCount() {
        let model = model()
        model.contacts = [Contact(id: "atlas", name: "Atlas")]
        model.threads["gone"] = ChatThread.sample("gone", state: ThreadState(history: [], running: false))
        model.threads["gone"]?.unreadCount = 3
        #expect(model.badgeCount == 0)
    }
}
