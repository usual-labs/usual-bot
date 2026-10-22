import Foundation
import Testing

@testable import HermesKit

/// Replays traffic recorded from a real gateway (anonymised; see `Fixtures/README.md`).
struct RecordedGatewayTests {
    struct Recording {
        let entries: [(direction: String, frame: JSONValue)]

        init(_ name: String) throws {
            let url = try #require(
                Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
            entries = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n")
                .map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
                .map { ($0["dir"]?.stringValue ?? "", $0["frame"] ?? .null) }
        }

        var inbound: [JSONValue] { entries.filter { $0.direction == "in" }.map(\.frame) }
    }

    @Test func legacyGatewayConnectsAndListsProfiles() async throws {
        let recording = try Recording("legacy-connect-roster")
        let socket = FakeSocket()
        let channel = JSONRPCChannel(socket: socket)
        await channel.start()

        let ready = try #require(recording.inbound.first)
        socket.deliver(String(decoding: try JSONEncoder().encode(ready), as: UTF8.self))
        #expect(try await channel.waitUntilReady().dialect == .legacy)

        async let reply = channel.call("profiles.list", params: ["include_sessions": true])
        try await waitUntil { socket.sent.count == 1 }
        #expect(socket.sent[0]["method"] == "profiles.list")
        guard case .object(var recorded) = try #require(recording.inbound.last) else {
            Issue.record("Recorded reply isn't an object")
            return
        }
        recorded["id"] = socket.sent[0]["id"]
        socket.deliver(String(decoding: try JSONEncoder().encode(JSONValue.object(recorded)), as: UTF8.self))

        let contacts = try await reply.decode(ProfileList.self).profiles.compactMap(Contact.init(profile:))
            .sorted(by: Contact.rosterOrder)
        // Most recently active first; the recording keeps the real activity times.
        #expect(contacts.map(\.name) == ["Writer", "Ops", "Scout", "Hermes"])
        #expect(
            contacts.map(\.preview) == [
                "Sample writer agent",  // Empty Bot Chat preview falls back to the description.
                "All 3 servers healthy, backups verified.",
                "Found 4 mentions of the comment bug across issues and Telegram.",
                "Done. Pushed release/0.3.1 and opened the PR.",  // Markdown stripped.
            ])
        #expect(contacts.first { $0.id == "scout" }?.tint == "hsl(180 68% 58%)")
        #expect(contacts.allSatisfy { $0.lastActive != nil })
    }

    @Test func legacyChatTurnStreamsIntoOneReply() async throws {
        let recording = try Recording("legacy-chat-turn")
        let socket = FakeSocket()
        let channel = JSONRPCChannel(socket: socket)
        await channel.start()

        let submitted = try #require(recording.entries.first { $0.direction == "out" }?.frame)
        #expect(submitted["method"] == "prompt.submit")
        let question = try #require(submitted["params"]?["text"]?.stringValue)
        var state = ThreadState()
        state.sendLocally(question)

        let events = recording.inbound.filter { $0["method"] == "event" }
        for frame in events {
            socket.deliver(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
        }
        var received = 0
        for await event in channel.events {
            #expect(event.sessionID == "live-1")
            state.apply(event)
            received += 1
            if received == events.count { break }
        }

        let answer = try #require(events.last?["params"]?["payload"]?["text"]?.stringValue)
        #expect(state.items.map(\.content) == [.user(question), .assistant(answer)])
        #expect(state.draft.isEmpty)
        #expect(!state.isRunning)
    }
}
