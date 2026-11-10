import Foundation
import Testing

@testable import HermesKit

private let launchRoom: JSONValue = [
    "room_id": "r1", "name": "Launch room",
    "members": [
        ["member_id": "m-writer", "profile": "writer", "handle": "writer"],
        ["member_id": "m-scout", "profile": "scout", "handle": "scout", "display_name": "Scout"],
    ],
    "updated_at": 1_792_735_200.5, "latest_seq": 4,
]

private func event(_ seq: Int, _ kind: String, actor: JSONValue = gateway, payload: JSONValue, id: String? = nil)
    -> JSONValue
{
    [
        "room_id": "r1", "seq": .number(Double(seq)), "event_id": .string(id ?? "e\(seq)"), "kind": .string(kind),
        "actor": actor, "payload": payload, "created_at": .number(1_792_735_000 + Double(seq)),
    ]
}

private let user: JSONValue = ["kind": "user", "id": "desktop"]
private let gateway: JSONValue = ["kind": "gateway", "id": "g1"]

private func message(_ seq: Int, _ text: String, thread: String? = nil, actor: JSONValue = user) -> JSONValue {
    event(
        seq, "message.user", actor: actor, payload: ["text": .string(text), "thread_id": .string(thread ?? "t\(seq)")],
        id: "u\(seq)")
}

/// A `room.context_set` payload, as `gateway/hosted_room_context.py` writes it.
private func context(_ routing: String, lead: String = "", purpose: String = "", notes: String = "") -> JSONValue {
    [
        "purpose": .string(purpose), "notes": .string(notes), "routing": .string(routing),
        "lead_member_id": .string(lead),
    ]
}

private func notices(_ state: RoomState) -> [String] {
    state.items.compactMap { if case .notice(let text) = $0.content { text } else { nil } }
}

private func state(_ events: [JSONValue]) throws -> RoomState {
    var state = RoomState(members: try #require(RoomSummary(launchRoom)).members)
    state.apply(events.compactMap(RoomEvent.init))
    return state
}

@Suite("Who answers in a room")
struct RoomRoutingStateTests {
    @Test func aLeadsPickIsSaidWithWhoLeads() throws {
        let assigned: JSONValue = [
            "discussion_event_id": "u1", "thread_id": "t1", "task_id": "k1", "lead_member_id": "m-writer",
            "member_ids": ["m-scout"], "fallback": false,
        ]
        var fallback = assigned
        if case .object(var object) = fallback {
            object["member_ids"] = ["m-writer"]
            object["fallback"] = true
            fallback = .object(object)
        }
        var shared = assigned
        if case .object(var object) = shared {
            object["member_ids"] = ["m-writer", "m-scout"]
            shared = .object(object)
        }
        let state = try state([
            message(1, "Who has the numbers?"), event(2, "room.assignment", payload: assigned),
            message(3, "And the copy?"), event(4, "room.assignment", payload: fallback),
            message(5, "And the plan?"), event(6, "room.assignment", payload: shared),
        ])
        #expect(
            notices(state) == [
                "Writer, the lead, gave this to Scout", "Writer, the lead, is taking this",
                "Writer, the lead, is taking this with Scout",
            ])
    }

    @Test func theRoomsPickIsSaidAndABotThatLeftIsLeftOut() throws {
        func routed(_ members: [JSONValue], everyone: Bool = false, fallback: Bool = false) -> JSONValue {
            [
                "discussion_event_id": "u1", "thread_id": "t1", "member_ids": .array(members),
                "everyone": .bool(everyone), "fallback": .bool(fallback),
            ]
        }
        let state = try state([
            event(1, "room.routed", payload: routed(["m-scout", "m-gone"])),
            event(2, "room.routed", payload: routed([], everyone: true)),
            event(3, "room.routed", payload: routed([], everyone: true, fallback: true)),
            event(4, "room.routed", payload: routed(["m-gone"])),
        ])
        #expect(
            notices(state) == [
                "The room picked Scout to answer", "The room picked everyone to answer",
                "The room couldn't pick who answers, so everyone will",
            ])
    }

    @Test func aChangeOfSettingsSaysWhatChanged() throws {
        let state = try state([
            event(1, "room.context_set", payload: context("lead", lead: "m-scout")),
            event(2, "room.context_set", payload: context("lead", lead: "m-scout", purpose: "Ship it")),
            event(3, "room.context_set", payload: context("lead", lead: "m-scout", purpose: "Ship it", notes: "n")),
            // Saved again unchanged: nothing to say.
            event(4, "room.context_set", payload: context("lead", lead: "m-scout", purpose: "Ship it", notes: "n")),
            event(5, "room.context_set", payload: context("auto", purpose: "Ship it", notes: "n")),
            // A gateway from before routing saves only these two.
            event(6, "room.context_set", payload: ["purpose": "", "notes": "n"]),
        ])
        #expect(
            notices(state) == [
                "Scout now leads, and picks who answers a message without an @mention",
                "The room's purpose is now “Ship it”", "The room's notes changed",
                "The room now picks who answers a message without an @mention",
                "Everyone now answers a message without an @mention",
            ])
    }

    /// The lead's status says only that it runs a turn, so the log says when that turn is the pick.
    @Test func theLeadIsChoosingUntilItsPickLands() throws {
        var state = try state([
            event(1, "room.context_set", payload: context("lead", lead: "m-writer")), message(2, "What's left?"),
        ])
        #expect(state.choosingLead == "m-writer")
        state.apply(
            [
                event(
                    3, "room.assignment",
                    payload: [
                        "discussion_event_id": "u2", "thread_id": "t2", "task_id": "k", "lead_member_id": "m-writer",
                        "member_ids": ["m-scout"], "fallback": false,
                    ])
            ].compactMap(RoomEvent.init))
        #expect(state.choosingLead == nil)
    }

    /// Hermes's `routes_through_lead`: an @mention, a routine's post and a message in a thread
    /// already going skip the lead.
    @Test func aMessageThatNamesSomeoneSkipsTheLead() throws {
        let lead = event(1, "room.context_set", payload: context("lead", lead: "m-writer"))
        #expect(try state([lead, message(2, "@scout go")]).choosingLead == nil)
        #expect(try state([lead, message(2, "@everyone go")]).choosingLead == nil)
        #expect(try state([lead, message(2, "hello@example.com wrote in")]).choosingLead == "m-writer")
        #expect(
            try state([lead, message(2, "Report", actor: ["kind": "user", "id": "cron:daily"])]).choosingLead == nil)
        #expect(try state([lead, message(2, "One"), message(3, "Two", thread: "t2")]).choosingLead == nil)
        #expect(try state([message(2, "What's left?")]).choosingLead == nil)
        // A stop ends the lead's turn with everyone else's.
        #expect(
            try state([lead, message(2, "Go"), event(3, "room.stop_requested", payload: ["cancel_id": "c"])])
                .choosingLead == nil)
    }
}

@Suite("A discussion paused at its cap")
struct RoomPauseTests {
    private func activity(_ seq: Int, _ discussion: String, _ status: String = "bounded", reason: String = "max_rounds")
        -> JSONValue
    {
        event(
            seq, "room.activity",
            payload: [
                "status": .string(status), "reason_code": .string(reason), "thread_id": "t",
                "discussion_event_id": .string(discussion),
            ])
    }

    private func continued(_ seq: Int, _ discussion: String, grant: Int) -> JSONValue {
        event(
            seq, "room.continued",
            payload: ["discussion_event_id": .string(discussion), "thread_id": "t", "grant": .number(Double(grant))])
    }

    @Test func theNewestMessagesDiscussionCanCarryOnEachTimeItPauses() throws {
        var state = try state([message(1, "Plan the launch"), activity(2, "u1")])
        #expect(state.pause == PausedDiscussion(discussionID: "u1", grant: 1, limit: .rounds))

        state.apply([continued(3, "u1", grant: 1)].compactMap(RoomEvent.init))
        #expect(state.pause == nil)
        #expect(notices(state).last == "The discussion carried on")

        state.apply([activity(4, "u1", reason: "max_messages")].compactMap(RoomEvent.init))
        #expect(state.pause == PausedDiscussion(discussionID: "u1", grant: 2, limit: .messages))
    }

    @Test func aNewMessageOrAStopEndsTheOffer() throws {
        #expect(try state([message(1, "Plan"), activity(2, "u1"), message(3, "Never mind")]).pause == nil)
        #expect(
            try state([
                message(1, "Plan"), activity(2, "u1"), event(3, "room.stop_requested", payload: ["cancel_id": "c"]),
            ]).pause == nil)
        // A stop that landed before the cap was written still ends it, as the gateway refuses it.
        #expect(
            try state([
                message(1, "Plan"), event(2, "room.stop_requested", payload: ["cancel_id": "c"]), activity(3, "u1"),
            ]).pause == nil)
        // An earlier message's cap, written late.
        #expect(try state([message(1, "Plan"), message(2, "Other"), activity(3, "u1")]).pause == nil)
        // A discussion that ended on its own has nothing to carry on.
        #expect(try state([message(1, "Plan"), activity(2, "u1", "settled", reason: "silent_round")]).pause == nil)
    }
}

@MainActor
@Suite("A room's settings on the gateway")
struct RoomSettingsTests {
    private func open() async throws -> (RoomThread, ScriptedGateway, JSONRPCChannel) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let room = RoomThread(summary: try #require(RoomSummary(launchRoom)), channel: { channel })
        return (room, gateway, channel)
    }

    /// Reads the room once, with `state` as `groups.state`'s answer and `events` as its log.
    private func sync(_ room: RoomThread, _ gateway: ScriptedGateway, state: JSONValue, events: [JSONValue] = [])
        async throws
    {
        let first = gateway.socket.sent.count
        async let synced: Void = room.sync()
        _ = try await gateway.answer(
            first, method: "groups.log", result: ["events": .array(events), "has_more": false])
        _ = try await gateway.answer(first + 1, method: "groups.state", result: state)
        await synced
    }

    @Test func readsTheLeadAndTheRoutingTheGatewayTakes() async throws {
        let (room, gateway, _) = try await open()
        try await sync(
            room, gateway,
            state: [
                "room": launchRoom, "context": context("lead", lead: "m-scout", purpose: "Ship it", notes: "Facts"),
                "driver_status": ["running": true, "max_continues": 5, "routing_modes": ["everyone", "lead", "auto"]],
            ])
        #expect(
            room.settings == RoomSettings(purpose: "Ship it", notes: "Facts", routing: .lead, leadID: "m-scout"))
        #expect(room.leadID == "m-scout")
        #expect(room.routingModes == [.everyone, .lead, .auto])
    }

    @Test func anOlderGatewayHasNoSettings() async throws {
        let (room, gateway, _) = try await open()
        try await sync(room, gateway, state: ["room": launchRoom, "driver_status": ["running": true]])
        #expect(room.settings == nil)
        #expect(room.routingModes.isEmpty)
        #expect(room.leadID == nil)
    }

    @Test func aGatewayFromBeforeAutoOffersEveryoneAndALead() async throws {
        let (room, gateway, _) = try await open()
        try await sync(
            room, gateway,
            state: ["room": launchRoom, "context": context("everyone"), "driver_status": ["running": true]])
        #expect(room.routingModes == [.everyone, .lead])
    }

    @Test func aGatewayWithOnlyAPurposeAndNotesIsNotSentRouting() async throws {
        let (room, gateway, channel) = try await open()
        try await sync(
            room, gateway,
            state: ["room": launchRoom, "context": ["purpose": "Ship it", "notes": ""], "driver_status": [:]])
        #expect(room.settings?.purpose == "Ship it")
        #expect(room.routingModes.isEmpty)

        let saved = Task { try await room.save(RoomSettings(purpose: "Ship it", notes: "New"), on: channel) }
        let params = try await gateway.answer(
            2, method: "groups.context", result: ["context": ["purpose": "Ship it", "notes": "New"]])
        try await saved.value
        #expect(params["routing"] == nil)
        #expect(params["lead_member_id"] == nil)
        #expect(params["notes"] == "New")
    }

    /// `groups.context` saves all four together, so a change of lead sends the purpose and notes too.
    @Test func savingSendsEverythingAndTakesTheGatewaysAnswer() async throws {
        let (room, gateway, channel) = try await open()
        try await sync(
            room, gateway,
            state: ["room": launchRoom, "context": context("everyone", purpose: "Ship it"), "driver_status": [:]])
        let changed = RoomSettings(purpose: "Ship it", notes: "", routing: .lead, leadID: "m-scout")
        let saved = Task { try await room.save(changed, on: channel) }
        let params = try await gateway.answer(
            2, method: "groups.context",
            result: ["context": context("lead", lead: "m-scout", purpose: "Ship it"), "event": [:]])
        try await saved.value
        let eventID = try #require(params["event_id"]?.stringValue)
        #expect(
            params == [
                "room_id": "r1", "event_id": .string(eventID), "purpose": "Ship it", "notes": "", "routing": "lead",
                "lead_member_id": "m-scout",
            ])
        #expect(room.settings == changed)
    }

    @Test func aLeadIsKeptOnlyWhileTheLeadPicks() {
        #expect(RoomSettings(routing: .everyone, leadID: "m-scout").leadID == nil)
        #expect(
            RoomSettings(routing: .auto, leadID: "m-scout").params(roomID: "r1", routes: true)["lead_member_id"] == "")
        #expect(RoomSettings(routing: .lead).problem != nil)
        #expect(RoomSettings(purpose: String(repeating: "a", count: 501)).problem != nil)
        #expect(RoomSettings(notes: String(repeating: "é", count: 2049)).problem != nil)
        #expect(RoomSettings(notes: String(repeating: "é", count: 2048)).problem == nil)
    }

    private func paused(maxContinues: JSONValue?) -> (state: JSONValue, events: [JSONValue]) {
        var status: [String: JSONValue] = ["running": true]
        status["max_continues"] = maxContinues
        return (
            ["room": launchRoom, "context": context("everyone"), "driver_status": .object(status)],
            [
                message(1, "Plan the launch"),
                event(
                    2, "room.activity",
                    payload: [
                        "status": "bounded", "reason_code": "max_rounds", "thread_id": "t1",
                        "discussion_event_id": "u1",
                    ]),
            ]
        )
    }

    @Test func carryingOnNamesTheDiscussion() async throws {
        let (room, gateway, _) = try await open()
        let paused = paused(maxContinues: 5)
        try await sync(room, gateway, state: paused.state, events: paused.events)
        let pause = try #require(room.pause)
        #expect(room.continuesLeft(pause) == 5)

        room.carryOn(pause)
        #expect(room.pause == nil)
        let params = try await gateway.answer(2, method: "groups.continue", result: ["continued": true, "event": [:]])
        #expect(params == ["room_id": "r1", "discussion_event_id": "u1"])
    }

    @Test func aRefusedCarryOnIsSaidAndOfferedAgain() async throws {
        let (room, gateway, _) = try await open()
        let paused = paused(maxContinues: 5)
        try await sync(room, gateway, state: paused.state, events: paused.events)
        room.carryOn(try #require(room.pause))
        _ = try await gateway.answer(2, method: "groups.continue", error: (4128, "This discussion is not paused."))
        try await waitUntilOnMain { room.pause != nil }
        #expect(notices(room.state).last == "The discussion didn't carry on: This discussion is not paused.")
    }

    @Test func aGatewayThatCantCarryOnOffersNothing() async throws {
        let (room, gateway, _) = try await open()
        let paused = paused(maxContinues: nil)
        try await sync(room, gateway, state: paused.state, events: paused.events)
        #expect(room.state.pause != nil)
        #expect(room.pause == nil)
    }

    @Test func leavingAPauseHidesItHereOnly() async throws {
        let (room, gateway, _) = try await open()
        let paused = paused(maxContinues: 5)
        try await sync(room, gateway, state: paused.state, events: paused.events)
        room.leavePaused(try #require(room.pause))
        #expect(room.pause == nil)
        #expect(gateway.socket.sent.count == 2)
    }
}

@MainActor
@Suite("A new room's routing")
struct NewRoomRoutingTests {
    private func signedIn() async -> (AppModel, ScriptedGateway) {
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        model.channel = channel
        return (model, gateway)
    }

    private let agents = [Contact(id: "writer", name: "Writer"), Contact(id: "scout", name: "Scout")]

    /// `groups.create` takes no routing, so the lead follows in `groups.context`.
    @Test func aLeadIsSetOnceTheRoomExists() async throws {
        let (model, gateway) = await signedIn()
        let created = Task {
            try await model.createRoom(named: "Launch", agents: agents, routing: .lead, lead: agents[1])
        }
        _ = try await gateway.answer(0, method: "groups.create", result: ["room": launchRoom])
        let params = try await gateway.answer(
            1, method: "groups.context", result: ["context": context("lead", lead: "scout")])
        #expect(params["room_id"] == "r1")
        #expect(params["routing"] == "lead")
        #expect(params["lead_member_id"] == "scout")
        #expect(params["purpose"] == "")
        #expect(try await created.value == "room:r1")
    }

    @Test func everyoneNeedsNoSecondCall() async throws {
        let (model, gateway) = await signedIn()
        let created = Task { try await model.createRoom(named: "Launch", agents: agents) }
        _ = try await gateway.answer(0, method: "groups.create", result: ["room": launchRoom])
        _ = try await created.value
        // The room's first read, not `groups.context`.
        try await waitUntil { gateway.socket.sent.count == 2 }
        #expect(gateway.socket.sent[1]["method"]?.stringValue == "groups.log")
    }

    @Test func aRefusedRoutingKeepsTheRoomAndSaysSo() async throws {
        let (model, gateway) = await signedIn()
        let created = Task { try await model.createRoom(named: "Launch", agents: agents, routing: .auto) }
        _ = try await gateway.answer(0, method: "groups.create", result: ["room": launchRoom])
        _ = try await gateway.answer(1, method: "groups.context", error: (5121, "routing must be 'everyone' or 'lead'"))
        let id = try await created.value
        let room = try #require(model.rooms[id])
        #expect(notices(room.state).first?.contains("routing must be 'everyone' or 'lead'") == true)
        #expect(model.contacts.map(\.id) == [id])
    }

    @Test func aGatewayWithoutRoomSettingsOffersNoChoice() async throws {
        let (model, gateway) = await signedIn()
        let asked = Task { await model.newRoomRouting() }
        _ = try await gateway.answer(
            0, method: "groups.capabilities", result: ["methods": ["groups.list", "groups.create", "groups.state"]])
        #expect(await asked.value.isEmpty)
    }

    @Test func aGatewayWithThemOffersWhatItsCallsShow() async throws {
        let (model, gateway) = await signedIn()
        let asked = Task { await model.newRoomRouting() }
        _ = try await gateway.answer(
            0, method: "groups.capabilities", result: ["methods": ["groups.context", "groups.continue"]])
        #expect(await asked.value == [.everyone, .lead, .auto])

        let older = Task { await model.newRoomRouting() }
        _ = try await gateway.answer(1, method: "groups.capabilities", result: ["methods": ["groups.context"]])
        #expect(await older.value == [.everyone, .lead])
    }

    @Test func aRoomAlreadyReadSaysExactly() async throws {
        let (model, _) = await signedIn()
        let summary = try #require(RoomSummary(launchRoom))
        let room = RoomThread.sample(summary, events: [], settings: RoomSettings())
        room.routingModes = [.everyone, .lead]
        model.rooms["room:r1"] = room
        #expect(await model.newRoomRouting() == [.everyone, .lead])
    }

    @Test func theDemoRoomHasALeadAndCanChangeIt() async throws {
        let model = AppModel.demo()
        let contact = try #require(model.sidebarContacts.first { $0.id == "room:launch" })
        let room = try #require(model.room(for: contact))
        #expect(room.leadID == "forge")
        #expect(notices(room.state).contains("Forge, the lead, is taking this with Atlas"))
        try await model.saveRoomSettings(contact, RoomSettings(routing: .auto))
        #expect(room.settings?.routing == .auto)
        #expect(room.leadID == nil)
    }
}
