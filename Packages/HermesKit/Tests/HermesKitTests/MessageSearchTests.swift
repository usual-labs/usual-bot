import Foundation
import Testing

@testable import HermesKit

@MainActor
struct MessageSearchTests {
    private func model(_ chats: [(Contact, [HistoryMessage])], rooms: [Contact.ID: RoomThread] = [:]) -> AppModel {
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        model.contacts = chats.map(\.0)
        for (contact, history) in chats {
            model.threads[contact.id] = ChatThread.sample(
                contact.id, state: ThreadState(history: history, running: false))
        }
        for (id, room) in rooms { model.rooms[id] = room }
        return model
    }

    private func agent(_ id: String, minutesAgo: Double) -> Contact {
        Contact(id: id, name: id.capitalized, lastActive: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60))
    }

    @Test func ignoresCaseAndAccentsAndNeedsEveryWordInAnyOrder() {
        let model = model([
            (
                agent("atlas", minutesAgo: 1),
                [
                    HistoryMessage(role: "user", text: "Book the CAFÉ near the office"),
                    HistoryMessage(role: "assistant", text: "Done: the café is booked for Friday."),
                ]
            )
        ])
        #expect(model.searchMessages("cafe").count == 2)
        #expect(model.searchMessages("friday Café").map(\.itemID) == [1])
        #expect(model.searchMessages("cafe saturday").isEmpty)
    }

    @Test func aQueryOfOneCharacterSearchesNothing() {
        let model = model([(agent("atlas", minutesAgo: 1), [HistoryMessage(role: "user", text: "a b c")])])
        #expect(MessageSearch(" a ") == nil)
        #expect(MessageSearch("   ") == nil)
        #expect(model.searchMessages("a").isEmpty)
        #expect(MessageSearch("ab") != nil)
    }

    @Test func searchesMessagesNotToolStepsOrHermesNotes() {
        let model = model([
            (
                agent("ops", minutesAgo: 1),
                [
                    HistoryMessage(role: "user", text: "Check the backups"),
                    HistoryMessage(role: "tool", name: "terminal", context: "verify-backups.sh"),
                    HistoryMessage(
                        role: "user", text: "Background process finished: verify-backups.sh",
                        displayKind: "process_complete", displayText: "Background Process Finished"),
                    HistoryMessage(role: "assistant", text: "All backups verified."),
                ]
            )
        ])
        model.threads["ops"]?.state.addNotice("backups compacted")
        #expect(model.searchMessages("backups").map(\.author) == [.agent, .you])
        #expect(model.searchMessages("verify-backups").isEmpty)
    }

    @Test func listsRecentChatsFirstAndNewestMessagesFirstUpToTheLimit() {
        let model = model([
            (
                agent("older", minutesAgo: 60),
                [HistoryMessage(role: "user", text: "deploy one"), HistoryMessage(role: "user", text: "deploy two")]
            ),
            (agent("newer", minutesAgo: 5), [HistoryMessage(role: "assistant", text: "deploy three")]),
        ])
        let hits = model.searchMessages("deploy")
        #expect(hits.map(\.contactID) == ["newer", "older", "older"])
        #expect(hits.map(\.snippet) == ["deploy three", "deploy two", "deploy one"])
        #expect(model.searchMessages("deploy", limit: 2).count == 2)
    }

    @Test func datedMessagesFromEveryChatInterleaveNewestFirst() {
        let model = model([
            (
                agent("recent", minutesAgo: 1),
                [
                    HistoryMessage(role: "user", text: "deploy at noon", timestamp: 100),
                    HistoryMessage(role: "user", text: "deploy, no time"),
                ]
            ),
            (
                agent("quiet", minutesAgo: 60),
                [
                    HistoryMessage(role: "user", text: "deploy at one", timestamp: 200),
                    HistoryMessage(role: "user", text: "deploy at dawn", timestamp: 50),
                ]
            ),
        ])
        #expect(
            model.searchMessages("deploy").map(\.snippet) == [
                "deploy at one", "deploy at noon", "deploy at dawn", "deploy, no time",
            ])
    }

    @Test func findsRoomMessagesUnderTheMembersSidebarName() throws {
        let summary = try #require(
            RoomSummary([
                "room_id": "r1", "name": "Launch",
                "members": [["member_id": "m1", "profile": "atlas", "handle": "atlas"]],
            ]))
        let events: [JSONValue] = [
            [
                "room_id": "r1", "seq": 1, "event_id": "e1", "kind": "message.member",
                "actor": ["kind": "member", "id": "m1"], "authority_epoch": 1,
                "payload": ["text": "The launch post is ready", "member_id": "m1"], "created_at": 1_800_000_000,
            ]
        ]
        let room = RoomThread.sample(summary, events: events)
        let atlas = Contact(id: "atlas", name: "Atlas Research")
        let model = model([(atlas, [])], rooms: [RoomSummary.contactID("r1"): room])
        model.contacts.append(Contact(room: summary))
        let hit = try #require(model.searchMessages("launch post").first)
        #expect(hit.contactID == "room:r1")
        #expect(hit.author == .member("Atlas Research"))
    }

    @Test func seesMessagesThatArriveAfterAnEarlierSearch() {
        let model = model([(agent("atlas", minutesAgo: 1), [HistoryMessage(role: "user", text: "hello")])])
        #expect(model.searchMessages("invoice").isEmpty)
        model.threads["atlas"]?.state.sendLocally("Send the invoice")
        #expect(model.searchMessages("invoice").count == 1)
        model.threads["atlas"]?.replaceTranscript(with: [HistoryMessage(role: "user", text: "hello again")])
        #expect(model.searchMessages("invoice").isEmpty)
    }

    @Test func plainTextLeavesOutTheVoiceFilesAReplyNames() {
        let text = "Voice memo saved to: /Users/me/.hermes/cache/audio/tts_20261102_232049_518752.mp3\nAnything else?"
        #expect(MessageSearch.plain(text) == "Anything else?")
    }

    @Test func plainTextDropsMarkdownAttachmentsAndQuotes() {
        let text =
            "> Atlas: an earlier reply\n\n## Plan\n- **Turbopuffer** for `search`\nMEDIA:/tmp/a.png\n@file:notes.md"
        #expect(MessageSearch.plain(text) == "Plan Turbopuffer for search")
    }

    @Test func theSnippetStartsNearTheFirstMatchAndMarksEachWord() throws {
        let search = try #require(MessageSearch("trial turbopuffer"))
        let plain =
            "We compared three vector databases over two weeks of real traffic, and Turbopuffer won. "
            + "Start the trial on Monday."
        let snippet = search.snippet(of: plain)
        #expect(snippet.text.hasPrefix("…"))
        #expect(snippet.text.contains("Turbopuffer won"))
        #expect(snippet.matches.map { snippet.text[$0].lowercased() } == ["turbopuffer", "trial"])

        let near = search.snippet(of: "Yes, and keep the old search as a trial on Turbopuffer.")
        #expect(near.text == "Yes, and keep the old search as a trial on Turbopuffer.")
    }

    @Test func theDemoFindsTurbopufferInAChatAndTheRoom() {
        let hits = AppModel.demo().searchMessages("turbopuffer")
        #expect(hits.contains { $0.contactID == "atlas" })
        #expect(hits.contains { $0.contactID.hasPrefix("room:") })
    }
}
