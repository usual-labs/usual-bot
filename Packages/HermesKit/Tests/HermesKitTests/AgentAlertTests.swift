import Foundation
import Testing

@testable import HermesKit

@MainActor
@Suite("Alerts about chats")
struct ChatAlertTests {
    private func makeChat(visible: Bool = false) -> (ChatThread, Box) {
        let thread = ChatThread.sample("forge", state: ThreadState())
        thread.isVisible = visible
        let box = Box()
        thread.alert = { box.alerts.append($0) }
        thread.alertWithdrawn = { box.withdrawn.append($0) }
        return (thread, box)
    }

    private final class Box {
        var alerts: [AgentAlert] = []
        var withdrawn: [String] = []
    }

    private func reply(_ thread: ChatThread, _ text: String) {
        thread.apply(GatewayEvent(type: "message.start", sessionID: "sample", seq: nil, payload: [:]))
        thread.apply(
            GatewayEvent(type: "message.complete", sessionID: "sample", seq: nil, payload: ["text": .string(text)]))
    }

    private func approval(_ id: String) -> ApprovalPrompt {
        ApprovalPrompt(id: id, sessionID: "sample", command: "rm -rf build", description: "", choices: [.once, .deny])
    }

    @Test func aReplyYouArentLookingAtAlertsOnce() {
        let (thread, box) = makeChat()
        reply(thread, "All done")
        #expect(box.alerts.map(\.kind) == [.message])
        #expect(box.alerts.first?.preview == "All done")
        #expect(thread.unreadCount == 1)
    }

    @Test func aReplyOnScreenDoesntAlert() {
        let (thread, box) = makeChat(visible: true)
        reply(thread, "All done")
        #expect(box.alerts.isEmpty)
    }

    @Test func aRequestAlertsOnceThoughTheGatewaySendsItAgain() {
        let (thread, box) = makeChat()
        thread.receive(approval("a1"))
        thread.announceRequests()
        thread.announceRequests()
        #expect(box.alerts.map(\.id) == ["a1"])
        #expect(box.alerts.first?.kind == .needsYou)
        #expect(box.alerts.first?.preview.contains("rm -rf build") == true)
    }

    @Test func aDetachedChatDoesntAlertAgainWhenItsRequestReturns() {
        let (thread, box) = makeChat()
        thread.receive(approval("a1"))
        thread.announceRequests()
        thread.detach()
        thread.receive(approval("a1"))
        thread.announceRequests()
        #expect(box.alerts.count == 1)
        #expect(box.withdrawn.isEmpty)
    }

    @Test func aRequestOverElsewhereTakesItsAlertBack() {
        let (thread, box) = makeChat()
        thread.receive(approval("a1"))
        thread.announceRequests()
        thread.apply(GatewayEvent(type: "request.cancel", sessionID: "sample", seq: nil, payload: ["id": "a1"]))
        #expect(box.withdrawn == ["a1"])
    }

    @Test func aRequestOnScreenDoesntAlertLater() {
        let (thread, box) = makeChat(visible: true)
        thread.receive(approval("a1"))
        thread.announceRequests()
        thread.isVisible = false
        thread.announceRequests()
        #expect(box.alerts.isEmpty)
    }
}

@MainActor
@Suite("Alerts on catching up")
struct CatchUpAlertTests {
    private func reattach(running: Bool, unread: Int, history: JSONValue) async throws -> (ChatThread, [AgentAlert]) {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let cached = CachedThread(
            state: ThreadState(), lastViewed: Date(timeIntervalSince1970: 1000), unreadCount: unread)
        let thread = ChatThread(contactID: "forge", cached: cached, channel: { channel })
        var alerts: [AgentAlert] = []
        thread.alert = { alerts.append($0) }
        thread.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(
            0, method: "session.resume",
            result: ["session_id": "live-1", "running": .bool(running), "messages": history])
        try await waitUntilOnMain { thread.isAttached }
        return (thread, alerts)
    }

    private let missed: JSONValue = [
        ["role": "user", "text": "Hi", "timestamp": 900],
        ["role": "assistant", "text": "Read before", "timestamp": 950],
        ["role": "assistant", "text": "Came in while you were away", "timestamp": 2000],
    ]

    @Test func aReplyMissedWhileAwayAlerts() async throws {
        let (thread, alerts) = try await reattach(running: false, unread: 0, history: missed)
        #expect(thread.unreadCount == 1)
        #expect(alerts.map(\.preview) == ["Came in while you were away"])
    }

    @Test func anUnreadReplyAlreadyCountedDoesntAlertAgain() async throws {
        let (_, alerts) = try await reattach(running: false, unread: 1, history: missed)
        #expect(alerts.isEmpty)
    }

    @Test func aTurnStillRunningAlertsWhenItEnds() async throws {
        let (_, alerts) = try await reattach(running: true, unread: 0, history: missed)
        #expect(alerts.isEmpty)
    }
}
