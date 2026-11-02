import Foundation
import Testing

@testable import HermesKit

/// Each message keeps when it was said, for the dates between messages.
struct MessageDateTests {
    @Test func historyKeepsTheGatewaysTimes() {
        let state = ThreadState(
            history: [
                HistoryMessage(role: "user", text: "Ship it", timestamp: 1_000),
                HistoryMessage(role: "tool", name: "terminal", toolCallId: "t1", timestamp: 1_010),
                HistoryMessage(role: "assistant", text: "Done.", timestamp: 1_020),
                HistoryMessage(role: "assistant", text: "No time"),
            ], running: false)

        #expect(
            state.items.map(\.date) == [
                Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 1_010),
                Date(timeIntervalSince1970: 1_020), nil,
            ])
    }

    @Test func whatArrivesLiveIsDatedWhenItArrives() {
        var state = ThreadState(
            history: [HistoryMessage(role: "assistant", text: "Hello", timestamp: 1_000)], running: false)
        let before = Date.now
        state.sendLocally("Hi")
        state.apply(GatewayEvent(type: "message.delta", sessionID: "s", seq: nil, payload: ["text": "Hey"]))
        state.apply(GatewayEvent(type: "message.complete", sessionID: "s", seq: nil, payload: [:]))

        let dates = state.items.dropFirst().compactMap(\.date)
        #expect(dates.count == 2)
        #expect(dates.allSatisfy { $0 >= before })
    }

    @Test func aCacheFromBeforeDatesStillOpens() throws {
        let old = Data(#"{"id": 3, "content": {"user": {"_0": "Hi"}}}"#.utf8)
        let item = try JSONDecoder().decode(TranscriptItem.self, from: old)
        #expect(item.content == .user("Hi"))
        #expect(item.date == nil)
    }

    @Test func aDateSurvivesTheCache() throws {
        let item = TranscriptItem(id: 1, content: .assistant("Hi"), date: Date(timeIntervalSince1970: 1_234.5))
        let copy = try JSONDecoder().decode(TranscriptItem.self, from: JSONEncoder().encode(item))
        #expect(copy.date == item.date)
    }

    @Test func roomItemsTakeTheirEventsTimes() throws {
        let summary: JSONValue = [
            "room_id": "r1", "name": "Launch",
            "members": [["member_id": "m-scout", "handle": "scout", "profile": "scout"]],
            "authority_gateway_id": "g1", "authority_epoch": 1, "revision": 1, "created_at": 1_792_700_000.0,
            "updated_at": 1_792_700_000.0, "idempotent": false, "latest_seq": 1,
        ]
        var room = RoomState(members: try #require(RoomSummary(summary)).members)
        let event: JSONValue = [
            "room_id": "r1", "seq": 1, "event_id": "e1", "kind": "message.user",
            "actor": ["kind": "user", "id": "u1"], "payload": ["text": "Hi", "thread_id": "t"],
            "created_at": 1_792_735_000,
        ]
        room.apply([event].compactMap(RoomEvent.init))
        #expect(room.items.first?.date == Date(timeIntervalSince1970: 1_792_735_000))
    }
}
