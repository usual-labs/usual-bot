import Foundation
import Testing

@testable import HermesKit

/// A Bot renamed on the gateway keeps its chat, opened again under the new ID. Hermes lets one live
/// session hold a chat, so the old session has to let go first.
@MainActor
struct ChatReleaseTests {
    private let resumed: JSONValue = ["session_id": "live-1", "running": false, "messages": .array([])]

    @Test func aMovedChatOpensOnlyOnceTheOldSessionLetsGo() async throws {
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        let old = ChatThread(contactID: "scout", channel: { channel })
        old.open(knownID: "stored-1", dialect: .legacy)
        _ = try await gateway.answer(0, method: "session.resume", result: resumed)
        try await waitUntilOnMain { old.isAttached }

        let moved = ChatThread(contactID: "finder", channel: { channel })
        moved.released = old.release()
        moved.open(knownID: "stored-1", dialect: .legacy)
        #expect(!old.isAttached)

        try await waitUntil { gateway.socket.sent.count > 1 }
        // sleep-ok: the resume must not go out before the close is answered, so there's no event to wait for
        try await Task.sleep(for: .milliseconds(100))
        #expect(gateway.socket.sent.count == 2)
        let closed = try await gateway.answer(1, method: "session.close", result: ["closed": true])
        #expect(closed["session_id"]?.stringValue == "live-1")
        _ = try await gateway.answer(2, method: "session.resume", result: resumed)
        try await waitUntilOnMain { moved.isAttached }
    }

    @Test func aChatNeverOpenedHasNothingToLetGo() {
        let thread = ChatThread(contactID: "scout", channel: { nil })
        #expect(thread.release() == nil)
    }
}
