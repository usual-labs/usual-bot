import Foundation
import Testing

@testable import HermesKit

/// A `groups.list` row shaped like `gateway/hosted_rooms.py::_room_from_row`.
private let launchRoom: JSONValue = [
    "room_id": "r1", "name": "Launch room",
    "members": [
        [
            "member_id": "m-writer", "profile": "writer", "handle": "writer",
            "target": ["kind": "local", "profile": "writer"],
        ],
        ["member_id": "m-scout", "profile": "scout", "handle": "scout", "display_name": "Scout"],
    ],
    "authority_gateway_id": "g1", "authority_epoch": 1, "revision": 3, "created_at": 1_792_700_000.0,
    "updated_at": 1_792_735_200.5, "idempotent": false, "latest_seq": 4,
]

/// A `groups.log` event shaped like `_event_from_row`.
private func event(_ seq: Int, _ kind: String, actor: JSONValue, payload: JSONValue, id: String? = nil) -> JSONValue {
    [
        "room_id": "r1", "seq": .number(Double(seq)), "event_id": .string(id ?? "e\(seq)"), "kind": .string(kind),
        "actor": actor, "authority_epoch": 1, "payload": payload, "created_at": .number(1_792_735_000 + Double(seq)),
        "idempotent": false,
    ]
}

private let user: JSONValue = ["kind": "user", "id": "u1"]
private func member(_ id: String) -> JSONValue { ["kind": "member", "id": .string(id)] }
private let gateway: JSONValue = ["kind": "gateway", "id": "g1"]

struct RoomParsingTests {
    @Test func readsAListedRoom() throws {
        let summary = try #require(RoomSummary(launchRoom))
        #expect(summary.name == "Launch room")
        #expect(summary.members.map(\.handle) == ["writer", "scout"])
        #expect(summary.members.map(\.profile) == ["writer", "scout"])
        #expect(summary.latestSeq == 4)
        #expect(RoomSummary.contactID("r1") == "room:r1")
        #expect(RoomSummary(["room_id": "gone", "disbanded_at": 1.0]) == nil)
    }

    @Test func userEventIDMatchesTheGateway() {
        // python3 -c 'import hashlib; print("user:" + hashlib.sha256(b"3f2b1c9e-…").hexdigest())'
        #expect(
            RoomThread.userEventID("3f2b1c9e-0d4a-4e7b-9a51-2c6f8e0b7d13")
                == "user:d53d79d26be9c338e90b3087ad941ce69103f4dcb0da56a4b78ba2f32ccc2122")
    }
}

struct RoomStateTests {
    private func state() throws -> RoomState {
        RoomState(members: try #require(RoomSummary(launchRoom)).members)
    }

    @Test func buildsTheConversationWithHandoffs() throws {
        var room = try state()
        room.apply(
            [
                event(1, "room.created", actor: ["kind": "system", "id": "room-control"], payload: [:]),
                event(2, "message.user", actor: user, payload: ["text": "Draft the 0.3.1 post", "thread_id": "t"]),
                event(3, "turn.started", actor: gateway, payload: ["member_id": "m-scout"]),
                event(
                    4, "message.member", actor: member("m-scout"),
                    payload: ["member_id": "m-scout", "text": "Found 4 mentions. @writer over to you.", "task_id": "k"]),
                event(
                    5, "message.member", actor: member("m-writer"),
                    payload: ["member_id": "m-writer", "text": "Draft ready."]),
            ].compactMap(RoomEvent.init))

        #expect(
            room.items.map(\.content) == [
                .user("Draft the 0.3.1 post"),
                .member(id: "m-scout", text: "Found 4 mentions. @writer over to you."),
                .notice("Scout handed off to Writer"),
                .member(id: "m-writer", text: "Draft ready."),
            ])
        #expect(room.cursor == 5)
    }

    @Test func eventsAreAppliedOnceInOrder() throws {
        var room = try state()
        let first = event(1, "message.user", actor: user, payload: ["text": "One", "thread_id": "t"])
        let second = event(2, "message.user", actor: user, payload: ["text": "Two", "thread_id": "t"])
        room.apply([second, first].compactMap(RoomEvent.init))
        room.apply([first, second].compactMap(RoomEvent.init))
        #expect(room.items.map(\.content) == [.user("One"), .user("Two")])
    }

    @Test func failuresAndRoomChangesBecomeNotices() throws {
        var room = try state()
        room.apply(
            [
                event(
                    1, "turn.failed", actor: gateway, payload: ["member_id": "m-writer", "error": "provider timeout"]),
                event(2, "member.unavailable", actor: gateway, payload: ["member_id": "m-scout"]),
                event(3, "room.renamed", actor: ["kind": "system", "id": "x"], payload: ["name": "Release room"]),
                event(4, "room.activity", actor: gateway, payload: ["status": "settled"]),
            ].compactMap(RoomEvent.init))
        #expect(
            room.items.map(\.content) == [
                .notice("Writer couldn't answer: provider timeout"), .notice("Scout is unavailable"),
                .notice("Room renamed to “Release room”"),
            ])
    }

    @Test func deferralsAndLimitsAreExplainedButPassesAreNot() throws {
        var room = try state()
        room.apply(
            [
                event(1, "message.user", actor: user, payload: ["text": "yoo everyone", "thread_id": "t"]),
                event(2, "turn.settled", actor: gateway, payload: ["member_id": "m-writer", "passed": true]),
                event(3, "turn.settled", actor: gateway, payload: ["member_id": "m-scout", "passed": true]),
                event(4, "turn.settled", actor: gateway, payload: ["member_id": "m-scout", "passed": false]),
                event(
                    5, "turn.deferred", actor: gateway,
                    payload: ["member_id": "m-writer", "reason": "busy elsewhere", "execution_generation": 1]),
                event(6, "room.activity", actor: gateway, payload: ["status": "bounded", "reason_code": "max_rounds"]),
                event(7, "turn.settled", actor: gateway, payload: ["member_id": "m-scout", "passed": true]),
            ].compactMap(RoomEvent.init))
        // Passes leave no line.
        #expect(
            room.items.map(\.content) == [
                .user("yoo everyone"), .notice("Writer\u{2019}s turn was put off: busy elsewhere"),
                .notice("The discussion reached its round limit"),
            ])
    }

    @Test func mentionsFollowTheGatewayRule() throws {
        let room = try state()
        #expect(RoomState.mentions(in: "Hi @writer, cc @Scout and @nobody.") == ["writer", "Scout", "nobody."])
        #expect(room.mentionedMembers(in: "@all please", excluding: "m-writer") == ["m-scout"])
        #expect(room.mentionedMembers(in: "@writer thoughts?", excluding: "m-writer").isEmpty)
    }
}

@MainActor
struct RoomThreadTests {
    private func open() async throws -> (RoomThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let room = RoomThread(summary: try #require(RoomSummary(launchRoom)), channel: { channel })
        return (room, gateway)
    }

    /// A room whose service is running and has nothing to do.
    private let idle: JSONValue = ["room": launchRoom, "driver_status": ["running": true]]

    private let status: JSONValue = [
        "room": launchRoom,
        "driver_status": [
            "running": true, "working": true, "member_activity": [["member_id": "m-writer", "status": "running"]],
            "pending_actions": [
                [
                    "kind": "approval", "task_id": "k1", "execution_generation": 2, "session_id": "s9",
                    "request_id": "req-1", "member_id": "m-writer",
                    "approval": [
                        "request_id": "req-1", "command": "git push", "description": "Push",
                        "choices": ["once", "session", "always", "deny"],
                    ],
                ]
            ],
        ],
    ]

    @Test func syncReadsTheLogThenTheStatus() async throws {
        let (room, gateway) = try await open()
        async let synced: Void = room.sync()
        let log = try await gateway.answer(
            0, method: "groups.log",
            result: [
                "events": [event(1, "message.user", actor: user, payload: ["text": "Hi", "thread_id": "t"])],
                "cursor": 1, "latest_seq": 1, "has_more": false,
            ])
        #expect(log == ["room_id": "r1", "since_seq": 0, "limit": 200])
        let state = try await gateway.answer(1, method: "groups.state", result: status)
        #expect(state == ["room_id": "r1"])
        await synced

        #expect(room.phase == .ready)
        #expect(room.state.items.map(\.content) == [.user("Hi")])
        #expect(room.working == ["m-writer"])
        let approval = try #require(room.approvals.first)
        #expect(approval.memberID == "m-writer")
        #expect(approval.prompt.choices == [.once, .deny])  // Rooms accept only these.
        #expect(room.activity == .needsYou)
    }

    @Test func olderGatewaysSayOnlyThatSomeoneIsAnswering() async throws {
        let (room, gateway) = try await open()
        async let synced: Void = room.sync()
        _ = try await gateway.answer(0, method: "groups.log", result: ["events": [], "has_more": false])
        // Hermes before 0.22.4: no member_activity.
        _ = try await gateway.answer(
            1, method: "groups.state",
            result: ["room": launchRoom, "driver_status": ["running": true, "working": true]])
        await synced
        #expect(room.working.isEmpty)
        #expect(room.isBusy)
        #expect(room.activity == .working)
    }

    @Test func queuedTurnsAreNotReplyingYet() async throws {
        let (room, gateway) = try await open()
        async let synced: Void = room.sync()
        _ = try await gateway.answer(0, method: "groups.log", result: ["events": [], "has_more": false])
        _ = try await gateway.answer(
            1, method: "groups.state",
            result: [
                "room": launchRoom,
                "driver_status": [
                    "running": true, "working": true,
                    "member_activity": [
                        ["member_id": "m-writer", "status": "running"], ["member_id": "m-scout", "status": "queued"],
                    ],
                ],
            ])
        await synced
        #expect(room.working == ["m-writer"])
    }

    @Test func sentMessageShowsUntilTheLogHasIt() async throws {
        let (room, gateway) = try await open()
        async let first: Void = room.sync()
        _ = try await gateway.answer(0, method: "groups.log", result: ["events": [], "has_more": false])
        _ = try await gateway.answer(1, method: "groups.state", result: idle)
        await first

        room.send("  @writer go  ")
        #expect(room.pending.map(\.text) == ["@writer go"])
        let sent = try await gateway.answer(2, method: "groups.send", result: ["accepted": true])
        let clientID = try #require(sent["event_id"]?.stringValue)
        #expect(sent["payload"] == ["text": "@writer go", "thread_id": .string(clientID)])

        _ = try await gateway.answer(
            3, method: "groups.log",
            result: [
                "events": [
                    event(
                        1, "message.user", actor: user,
                        payload: ["text": "@writer go", "thread_id": .string(clientID)],
                        id: RoomThread.userEventID(clientID))
                ], "has_more": false,
            ])
        _ = try await gateway.answer(4, method: "groups.state", result: idle)
        try await waitUntilOnMain { room.pending.isEmpty }
        #expect(room.state.items.map(\.content) == [.user("@writer go")])
    }

    @Test func aMessageThatDidntSendGoesBackToTheBox() async throws {
        let (room, gateway) = try await open()
        async let first: Void = room.sync()
        _ = try await gateway.answer(0, method: "groups.log", result: ["events": [], "has_more": false])
        _ = try await gateway.answer(1, method: "groups.state", result: idle)
        await first

        room.send("@writer go")
        _ = try await gateway.answer(2, method: "groups.send", error: (4123, "worker unavailable"))
        try await waitUntilOnMain { room.pending.isEmpty }
        #expect(room.unsent == "@writer go")
        guard case .notice(let text) = room.state.items.last?.content else {
            Issue.record("expected a notice")
            return
        }
        #expect(text.contains("worker unavailable"))
    }

    @Test func roomServiceDownStopsSending() async throws {
        let (room, gateway) = try await open()
        async let synced: Void = room.sync()
        _ = try await gateway.answer(0, method: "groups.log", result: ["events": [], "has_more": false])
        _ = try await gateway.answer(1, method: "groups.state", result: ["room": launchRoom])
        await synced
        #expect(!room.driverRunning)
        #expect(!room.canSend)
    }

    @Test func createSeatsAgentsByProfile() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        async let created = RoomThread.create(named: " Launch room ", profiles: ["writer", "scout"], on: channel)

        let params = try await gateway.answer(0, method: "groups.create", result: ["room": launchRoom])
        let roomID = try #require(params["room_id"]?.stringValue)
        #expect(UUID(uuidString: roomID) != nil)
        // The gateway checks these exact fields (gateway/hosted_room_discussion.py `_validate_member`).
        #expect(
            params == [
                "room_id": .string(roomID), "name": "Launch room",
                "members": [
                    [
                        "member_id": "writer", "profile": "writer", "handle": "writer",
                        "target": ["kind": "local", "profile": "writer"],
                    ],
                    [
                        "member_id": "scout", "profile": "scout", "handle": "scout",
                        "target": ["kind": "local", "profile": "scout"],
                    ],
                ],
            ])
        let summary = try await created
        #expect(summary.id == "r1")
        #expect(Contact(room: summary).kind == .room(memberIDs: ["writer", "scout"]))
    }

    @Test func createReportsTheGatewaysReason() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let created = Task { try await RoomThread.create(named: "Solo", profiles: ["writer"], on: channel) }
        _ = try await gateway.answer(
            0, method: "groups.create", error: (5111, "members must contain between 2 and 6 entries"))
        await #expect(throws: GatewayError.rpc(code: 5111, message: "members must contain between 2 and 6 entries")) {
            try await created.value
        }
    }

    @Test func approvalIsAnsweredForTheExactTask() async throws {
        let (room, gateway) = try await open()
        async let first: Void = room.sync()
        _ = try await gateway.answer(0, method: "groups.log", result: ["events": [], "has_more": false])
        _ = try await gateway.answer(1, method: "groups.state", result: status)
        await first

        room.answer(try #require(room.approvals.first), with: .once)
        let params = try await gateway.answer(2, method: "groups.approve", result: ["approved": true])
        #expect(
            params == [
                "room_id": "r1", "member_id": "m-writer", "task_id": "k1", "execution_generation": 2, "choice": "once",
                "request_id": "req-1",
            ])
        #expect(room.state.items.last?.content == .notice("You allowed “git push” once"))
    }
}

@Suite("Room editing")
@MainActor
struct RoomEditingTests {
    private func connected() async -> (ScriptedGateway, JSONRPCChannel, RoomThread) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let room = RoomThread(summary: RoomSummary(launchRoom)!, channel: { channel })
        return (gateway, channel, room)
    }

    @Test func renamingAsksTheGatewayWithAnEventIDThatMakesARepeatHarmless() async throws {
        let (gateway, channel, room) = await connected()
        let done = Task { try await room.rename(to: "Launch", on: channel) }
        let params = try await gateway.answer(0, method: "groups.rename", result: ["room": launchRoom])
        try await done.value
        #expect(params["room_id"] == "r1")
        #expect(params["name"] == "Launch")
        #expect(params["event_id"]?.stringValue?.isEmpty == false)
    }

    @Test func aFailedRenameKeepsTheOldName() async throws {
        let (gateway, channel, room) = await connected()
        let done = Task { try await room.rename(to: "Launch", on: channel) }
        _ = try await gateway.answer(0, method: "groups.rename", error: (4123, "worker unavailable"))
        await #expect(throws: GatewayError.self) { try await done.value }
        #expect(room.name == "Launch room")
    }

    @Test func deletingDisbandsTheRoom() async throws {
        let (gateway, channel, room) = await connected()
        let done = Task { try await room.disband(on: channel) }
        let params = try await gateway.answer(0, method: "groups.disband", result: ["tombstone": [:]])
        try await done.value
        #expect(params["room_id"] == "r1")
    }

    @Test func aStoppedTurnOffersARetryAndNeedsYou() async throws {
        let (gateway, _, room) = await connected()
        let sync = Task { await room.sync() }
        _ = try await gateway.answer(0, method: "groups.log", result: ["events": [], "has_more": false])
        _ = try await gateway.answer(
            1, method: "groups.state",
            result: ["driver_status": ["running": true, "pending_actions": [["kind": "retry", "task_id": "t1"]]]])
        await sync.value
        #expect(room.retries == ["t1"])
        #expect(room.activity == .needsYou)

        room.retry("t1")
        #expect(room.retries.isEmpty)
        let params = try await gateway.answer(2, method: "groups.retry", result: ["retried": true])
        #expect(params["task_id"] == "t1")
        #expect(params["room_id"] == "r1")
    }

    @Test func aFailedRetryIsSaid() async throws {
        let (gateway, _, room) = await connected()
        room.retry("t1")
        _ = try await gateway.answer(0, method: "groups.retry", error: (4123, "worker unavailable"))
        try await waitUntilOnMain { !room.state.items.isEmpty }
        guard case .notice(let text) = room.state.items.last?.content else {
            Issue.record("expected a notice")
            return
        }
        #expect(text.contains("worker unavailable"))
    }
}

@Suite("Room edits and the room list")
@MainActor
struct RoomListRaceTests {
    private func signedIn() async throws -> (AppModel, ScriptedGateway, Contact) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") }, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        model.channel = channel
        let summary = try #require(RoomSummary(launchRoom))
        let contact = Contact(room: summary)
        model.contacts = [contact]
        model.rooms[contact.id] = RoomThread(summary: summary, channel: { nil })
        return (model, gateway, contact)
    }

    @Test func aListReadBeforeADeleteCannotBringTheRoomBack() async throws {
        let (model, gateway, contact) = try await signedIn()
        let channel = try #require(model.channel)
        let list = Task { await model.refreshRooms(on: channel) }
        try await waitUntil { gateway.socket.sent.count == 1 }
        let delete = Task { try await model.deleteRoom(contact) }
        _ = try await gateway.answer(1, method: "groups.disband", result: ["tombstone": [:]])
        try await delete.value
        _ = try await gateway.answer(0, method: "groups.list", result: ["rooms": [launchRoom]])
        #expect(await list.value == nil)
        #expect(model.contacts.isEmpty)
        #expect(model.room(for: contact) == nil)
    }

    @Test func aListReadBeforeARenameCannotPutTheOldNameBack() async throws {
        let (model, gateway, contact) = try await signedIn()
        let channel = try #require(model.channel)
        let list = Task { await model.refreshRooms(on: channel) }
        try await waitUntil { gateway.socket.sent.count == 1 }
        let rename = Task { try await model.renameRoom(contact, to: "Launch") }
        _ = try await gateway.answer(1, method: "groups.rename", result: ["room": launchRoom])
        try await rename.value
        _ = try await gateway.answer(0, method: "groups.list", result: ["rooms": [launchRoom]])
        #expect(await list.value == nil)
        #expect(model.contacts.first?.name == "Launch")
        #expect(model.room(for: contact)?.name == "Launch")
    }

    @Test func aFailedDeleteKeepsTheRoom() async throws {
        let (model, gateway, contact) = try await signedIn()
        let delete = Task { try await model.deleteRoom(contact) }
        _ = try await gateway.answer(0, method: "groups.disband", error: (4123, "worker unavailable"))
        await #expect(throws: GatewayError.self) { try await delete.value }
        #expect(model.contacts.count == 1)
    }
}

@MainActor
@Suite("Alerts about rooms")
struct RoomAlertTests {
    private final class Box {
        var alerts: [AgentAlert] = []
        var withdrawn: [String] = []
    }

    private func sync(
        _ room: RoomThread, _ gateway: ScriptedGateway, from index: Int, events: JSONValue, status: JSONValue
    )
        async throws
    {
        let finished = Task { await room.sync() }
        _ = try await gateway.answer(index, method: "groups.log", result: ["events": events, "has_more": false])
        _ = try await gateway.answer(index + 1, method: "groups.state", result: status)
        await finished.value
    }

    private func status(_ actions: JSONValue) -> JSONValue {
        ["driver_status": ["running": true, "working": false, "pending_actions": actions]]
    }

    private let retry: JSONValue = ["kind": "retry", "task_id": "t1"]

    private func openRoom() async throws -> (RoomThread, ScriptedGateway, Box) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let room = RoomThread(summary: try #require(RoomSummary(launchRoom)), channel: { channel })
        let box = Box()
        room.alert = { box.alerts.append($0) }
        room.alertWithdrawn = { box.withdrawn.append($0) }
        return (room, gateway, box)
    }

    private func reply(_ seq: Int, secondsAgo: Double) -> JSONValue {
        [
            "room_id": "r1", "seq": .number(Double(seq)), "event_id": .string("e\(seq)"), "kind": "message.member",
            "actor": member("m-scout"), "authority_epoch": 1, "payload": ["text": "Found it"],
            "created_at": .number(Date().addingTimeInterval(-secondsAgo).timeIntervalSince1970), "idempotent": false,
        ]
    }

    @Test func aRoomsFirstLoadIsntNewsButTheNextReplyIs() async throws {
        let (room, gateway, box) = try await openRoom()
        try await sync(room, gateway, from: 0, events: [reply(1, secondsAgo: 60)], status: status([]))
        #expect(box.alerts.isEmpty)

        try await sync(room, gateway, from: 2, events: [reply(2, secondsAgo: -5)], status: status([]))
        #expect(box.alerts.map(\.kind) == [.message])
        #expect(box.alerts.first?.subtitle == "Scout")
        #expect(box.alerts.first?.preview == "Found it")
    }

    @Test func aStoppedReplyAlertsOnceThenGoesWhenItsDone() async throws {
        let (room, gateway, box) = try await openRoom()
        try await sync(room, gateway, from: 0, events: [], status: status([retry]))
        try await sync(room, gateway, from: 2, events: [], status: status([retry]))
        #expect(box.alerts.map(\.id) == ["t1"])
        #expect(box.alerts.first?.kind == .needsYou)

        try await sync(room, gateway, from: 4, events: [], status: status([]))
        #expect(box.withdrawn == ["t1"])
    }

    @Test func aRoomOnScreenDoesntAlert() async throws {
        let (room, gateway, box) = try await openRoom()
        room.isVisible = true
        try await sync(room, gateway, from: 0, events: [reply(1, secondsAgo: -5)], status: status([retry]))
        #expect(box.alerts.isEmpty)
    }
}

@Suite struct RoomPreviewTests {
    @Test func aPreviewLeavesOutTheFilesAMessageCarries() {
        #expect(
            RoomThread.readable("Here's the **teaser**.\nMEDIA:/home/hermes/.hermes/cache/video/teaser.mp4")
                == "Here's the teaser.")
        #expect(RoomThread.readable("MEDIA:/home/hermes/.hermes/cache/video/teaser.mp4") == "Sent a file")
    }
}
