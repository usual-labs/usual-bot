import Foundation
import Testing

@testable import HermesKit

/// A `connection.request` payload as `ConnectionOperation.request_payload` shapes it.
private func payload(op: String = "op-1", seq: Int = 2, targets: [JSONValue], settled: String? = nil) -> JSONValue {
    var value: [String: JSONValue] = [
        "op_id": .string(op), "seq": .number(Double(seq)), "deadline_at": 1_800_000_000, "timeout_seconds": 300,
        "targets": .array(targets), "tool_call_id": "call-1",
    ]
    if let settled {
        value["settled"] = true
        value["settled_at"] = 1_800_000_100
        value["settled_by"] = .string(settled)
    }
    return .object(value)
}

private func target(
    _ name: String, kind: String = "connector", action: String = "connect", state: String = "initiated",
    url: String? = "https://connect.example.com/\("x")", extra: [String: JSONValue] = [:]
) -> JSONValue {
    var value: [String: JSONValue] = [
        "name": .string(name), "kind": .string(kind), "action": .string(action), "state": .string(state),
        "resolved": .bool(state == "connected" || state == "skipped"),
    ]
    if let url { value["connect_url"] = .string(url) }
    return .object(value.merging(extra) { $1 })
}

struct ConnectionRequestTests {
    @Test func readsTheRequestHermesSends() throws {
        let request = try #require(
            ConnectionRequest(
                payload(targets: [
                    target("gmail"), target("google_drive", state: "pending", url: nil),
                    target("linear", kind: "mcp", action: "authorize", url: "https://linear.example.com/oauth"),
                ]), sessionID: "live-1"))
        #expect(request.id == "op-1")
        #expect(request.seq == 2)
        #expect(request.deadline == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(request.targets.map(\.title) == ["Gmail", "Google Drive", "Linear"])
        #expect(request.targets[0].offer == .signIn(URL(string: "https://connect.example.com/x")!))
        #expect(request.targets[1].offer == .preparing)
        #expect(request.targets[2].kind == .mcp)
        #expect(!request.isList)
        #expect(!request.isSettled)
    }

    @Test func offersWhatEachAppNeeds() throws {
        let request = try #require(
            ConnectionRequest(
                payload(targets: [
                    target("github", kind: "mcp", action: "install", state: "pending", url: nil),
                    target("sentry", kind: "mcp", action: "enable", state: "pending", url: nil),
                    target(
                        "stripe", kind: "mcp", action: "install", state: "pending", url: nil,
                        extra: ["required_env": [["name": "STRIPE_KEY", "required": true, "secret": true]]]),
                    target("figma", kind: "plugin", action: "install", state: "pending", url: nil),
                    target("slack", state: "failed", url: nil, extra: ["detail": "The workspace refused it."]),
                    target("notion", state: "expired", url: nil),
                    target("gmail", state: "connected", url: nil),
                    target("drive", state: "skipped", url: nil),
                    target("evil", url: "javascript:alert(1)"),
                ]), sessionID: "live-1"))
        #expect(
            request.targets.map(\.offer) == [
                .approve, .approve, .elsewhere, .elsewhere, .retry, .retry, .none, .none, .preparing,
            ])
        #expect(request.targets[4].detail == "The workspace refused it.")
        #expect(request.open.map(\.name) == ["github", "sentry", "stripe", "figma", "slack", "notion", "evil"])
    }

    @Test func readsAListOfAppsAndRefusesNothingToAnswer() throws {
        var list = payload(targets: [])
        if case .object(var object) = list {
            object["display"] = ["suggested": ["gmail", "google_calendar"]]
            list = .object(object)
        }
        let request = try #require(ConnectionRequest(list, sessionID: "live-1"))
        #expect(request.isList)
        #expect(request.suggested == ["Gmail", "Google Calendar"])
        #expect(ConnectionRequest(payload(targets: []), sessionID: "live-1") == nil)
        #expect(ConnectionRequest(["seq": 1, "targets": [["name": "gmail"]]], sessionID: "live-1") == nil)
    }

    @Test func framesApplyInOrderAndOnlyToTheirRequest() throws {
        var request = try #require(ConnectionRequest(payload(seq: 3, targets: [target("gmail")]), sessionID: "s"))
        let older = request.apply(payload(seq: 2, targets: [target("gmail", state: "failed")]))
        let another = request.apply(payload(op: "op-2", seq: 9, targets: [target("gmail", state: "failed")]))
        #expect(!older && !another)
        #expect(request.targets[0].state == .initiated)
        // An account frame leaves the link out; the one held stays.
        let account = request.apply(payload(seq: 4, targets: [target("gmail", url: nil)]))
        #expect(account)
        #expect(request.targets[0].connectURL != nil)
        let settled = request.apply(
            payload(seq: 5, targets: [target("gmail", state: "connected")], settled: "all_resolved"))
        #expect(settled)
        #expect(request.ending == .allResolved)
    }

    @Test func theEndSaysWhatHappenedToEachApp() throws {
        let frame = payload(
            targets: [
                target("gmail", state: "connected"), target("slack", state: "skipped"),
                target("notion", state: "not_connected"),
            ], settled: "deadline")
        let request = try #require(ConnectionRequest(frame, sessionID: "s"))
        #expect(
            request.endNotices == [
                "You connected Gmail", "You chose Not now for Slack", "Nobody finished connecting Notion in time.",
            ])
    }
}

@MainActor
struct ConnectionChatTests {
    private func openThread(pending: JSONValue? = nil) async throws -> (ChatThread, ScriptedGateway) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let thread = ChatThread(contactID: "scout", channel: { channel })
        thread.open(knownID: "stored-1", dialect: .legacy)
        var result: [String: JSONValue] = ["session_id": "live-1", "running": true, "messages": .array([])]
        if let pending { result["pending_connection"] = pending }
        _ = try await gateway.answer(0, method: "session.resume", result: .object(result))
        try await waitUntilOnMain { thread.isAttached }
        return (thread, gateway)
    }

    private func event(_ type: String, _ payload: JSONValue) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "live-1", seq: nil, payload: payload)
    }

    @Test func aRequestStillWaitingArrivesWithTheChat() async throws {
        let (thread, _) = try await openThread(pending: payload(targets: [target("gmail")]))
        #expect(thread.connection?.request.id == "op-1")
        #expect(thread.activity == .needsYou)
    }

    @Test func theEventOpensTheCardAndConnectOpensTheSignInPage() async throws {
        let (thread, gateway) = try await openThread()
        thread.apply(event("connection.request", payload(targets: [target("gmail")])))
        let card = try #require(thread.connection)
        #expect(thread.connect(card.request.targets[0]) == URL(string: "https://connect.example.com/x"))
        #expect(thread.connection?.opened == ["gmail"])
        // sleep-ok: opening the page sends nothing, so there is no event to wait for
        try await Task.sleep(for: .milliseconds(30))
        #expect(gateway.socket.sent.count == 1)

        thread.apply(event("connection.update", payload(seq: 3, targets: [target("gmail", state: "connected")])))
        #expect(thread.connection?.request.targets[0].state == .connected)
        thread.apply(
            event(
                "connection.update",
                payload(seq: 4, targets: [target("gmail", state: "connected")], settled: "all_resolved")))
        #expect(thread.connection == nil)
        #expect(thread.state.items.last?.content == .notice("You connected Gmail"))
        #expect(thread.activity != .needsYou)
    }

    @Test func notNowSkipsEveryAppStillOpen() async throws {
        let (thread, gateway) = try await openThread(
            pending: payload(targets: [target("gmail", state: "connected"), target("slack"), target("notion")]))
        thread.skipConnection()
        let params = try await gateway.answer(
            1, method: "connection.respond", result: ["status": "ok", "settled": true])
        #expect(
            params == [
                "owner": ["type": "session", "session_id": "live-1"], "op_id": "op-1",
                "result": [
                    "targets": [["name": "slack", "status": "skipped"], ["name": "notion", "status": "skipped"]]
                ],
            ])
        try await waitUntilOnMain { thread.connection == nil }
        #expect(
            thread.state.items.suffix(2).map(\.content) == [
                .notice("You connected Gmail"), .notice("You chose Not now for Slack and Notion"),
            ])
    }

    @Test func anMCPInstallIsApprovedAndWaitsForHermes() async throws {
        let (thread, gateway) = try await openThread(
            pending: payload(targets: [target("github", kind: "mcp", action: "install", state: "pending", url: nil)]))
        #expect(thread.connect(try #require(thread.connection?.request.targets.first)) == nil)
        #expect(thread.connection?.busy == ["github"])
        let params = try await gateway.answer(
            1, method: "connection.respond", result: ["status": "ok", "settled": false])
        #expect(params["result"] == ["targets": [["name": "github", "status": "approved"]]])
        try await waitUntilOnMain { thread.connection?.busy.isEmpty == true }
        #expect(thread.connection != nil)
    }

    @Test func tryAgainGetsAFreshLinkForAHostedApp() async throws {
        let (thread, gateway) = try await openThread(
            pending: payload(targets: [target("gmail", state: "expired", url: nil)]))
        thread.retry(try #require(thread.connection?.request.targets.first))
        let params = try await gateway.answer(
            1, method: "connectors.connect",
            result: payload(seq: 5, targets: [target("gmail", url: "https://connect.example.com/new")]))
        #expect(
            params == [
                "owner": ["type": "session", "session_id": "live-1"], "connectors": ["gmail"], "reconnect": true,
            ])
        try await waitUntilOnMain {
            thread.connection?.request.targets.first?.offer == .signIn(URL(string: "https://connect.example.com/new")!)
        }
    }

    @Test func tryAgainRunsAFailedMCPServerAgain() async throws {
        let (thread, gateway) = try await openThread(
            pending: payload(targets: [target("linear", kind: "mcp", action: "authorize", state: "failed", url: nil)]))
        thread.retry(try #require(thread.connection?.request.targets.first))
        let params = try await gateway.answer(
            1, method: "connection.respond", result: ["status": "ok", "settled": false])
        #expect(params["result"] == ["targets": [["name": "linear", "status": "approved"]]])
    }

    @Test func aRefusedAnswerSaysWhyAndKeepsTheCard() async throws {
        let (thread, gateway) = try await openThread(
            pending: payload(targets: [target("gmail", state: "failed", url: nil)]))
        thread.retry(try #require(thread.connection?.request.targets.first))
        _ = try await gateway.answer(
            1, method: "connectors.connect", error: (4032, "Sign in to use connectors."))
        try await waitUntilOnMain { thread.connection?.problem != nil }
        #expect(thread.connection?.problem == "Sign in to the Nous Portal in the Hermes app first, then try again.")
    }

    @Test func aRequestHermesAlreadyLetGoOfLeavesWithANotice() async throws {
        let (thread, gateway) = try await openThread(pending: payload(targets: [target("gmail")]))
        thread.skipConnection()
        _ = try await gateway.answer(
            1, method: "connection.respond", error: (4004, "No open operation with that op_id."))
        try await waitUntilOnMain { thread.connection == nil }
        #expect(thread.state.items.last?.content == .notice("The request to connect Gmail had already ended."))
    }

    @Test func theCardWaitsOfflineAndEndsIfHermesNoLongerHasIt() async throws {
        let (thread, gateway) = try await openThread(pending: payload(targets: [target("gmail")]))
        thread.detach()
        #expect(thread.connection != nil)
        #expect(!thread.isAttached)

        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            1, method: "session.resume", result: ["session_id": "live-2", "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }
        #expect(thread.connection == nil)
        #expect(
            thread.state.items.last?.content
                == .notice("The request to connect Gmail ended while this device was away."))
    }

    @Test func aReattachKeepsWhatThisDeviceOpened() async throws {
        let pending = payload(targets: [target("gmail")])
        let (thread, gateway) = try await openThread(pending: pending)
        _ = thread.connect(try #require(thread.connection?.request.targets.first))
        thread.detach()
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            1, method: "session.resume",
            result: ["session_id": "live-1", "running": true, "messages": .array([]), "pending_connection": pending])
        try await waitUntilOnMain { thread.isAttached }
        #expect(thread.connection?.opened == ["gmail"])
    }

    @Test func aStoppedReplyEndsTheCard() async throws {
        let (thread, _) = try await openThread(pending: payload(targets: [target("gmail")]))
        thread.apply(
            event(
                "connection.update",
                payload(seq: 3, targets: [target("gmail", state: "not_connected")], settled: "interrupt")))
        #expect(thread.connection == nil)
        #expect(thread.state.items.last?.content == .notice("Gmail didn't connect: the reply was stopped."))
    }
}
