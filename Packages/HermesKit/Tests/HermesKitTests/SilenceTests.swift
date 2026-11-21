import Foundation
import Testing

@testable import HermesKit

/// A Bot answering `[SILENT]` chose not to reply. It's no message, live or from history.
struct SilenceTests {
    private func event(_ type: String, _ payload: JSONValue = [:]) -> GatewayEvent {
        GatewayEvent(type: type, sessionID: "s1", seq: nil, payload: payload)
    }

    @Test func markersAndProse() {
        for marker in ["[SILENT]", "NO_REPLY", " no_reply. ", "*NO_REPLY*", "[静默]", "No reply"] {
            #expect(Silence.isMarker(marker), "\(marker)")
        }
        for prose in ["[SILENT", "Silent night", "The status is NO_REPLY needed.", ""] {
            #expect(!Silence.isMarker(prose), "\(prose)")
        }
        #expect(Silence.withoutClosingMarker("Done.\n\nNO_REPLY") == "Done.")
        #expect(Silence.withoutClosingMarker("Say NO_REPLY") == "Say NO_REPLY")
    }

    @Test func aSilentReplyInHistoryLeavesNoBubble() {
        let history = [
            HistoryMessage(role: "user", text: "Ping"),
            HistoryMessage(role: "assistant", text: "[SILENT]"),
            HistoryMessage(role: "user", text: "And now?"),
            HistoryMessage(role: "assistant", text: "Here.\n\n[SILENT]"),
        ]
        let items = ThreadState(history: history, running: false).items.map(\.content)
        #expect(items == [.user("Ping"), .user("And now?"), .assistant("Here.")])
    }

    @Test func aStreamedMarkerNeverShows() {
        var state = ThreadState()
        state.apply(event("message.start"))
        state.apply(event("message.delta", ["text": "[SIL"]))
        #expect(state.draft.isEmpty)
        state.apply(event("message.delta", ["text": "ENT]"]))
        #expect(state.draft.isEmpty)
        state.apply(event("message.complete", ["text": "[SILENT]", "status": "complete"]))
        #expect(state.items.isEmpty)
    }

    @Test func aClosingMarkerIsHeldBackWhileStreaming() {
        var state = ThreadState()
        state.apply(event("message.start"))
        state.apply(event("message.delta", ["text": "Paris.\n\nNO"]))
        #expect(state.draft == "Paris.")
        state.apply(event("message.delta", ["text": "_REPLY"]))
        #expect(state.draft == "Paris.")
        state.apply(event("message.complete", ["status": "complete"]))
        #expect(state.items.map(\.content) == [.assistant("Paris.")])
    }

    @Test func aSilentReplyIsntUnread() {
        let history = [
            HistoryMessage(
                role: "user", text: "[Cronjob \"ping\" output — x]\n\nNothing", displayKind: "internal_notification"),
            HistoryMessage(role: "assistant", text: "[SILENT]"),
        ]
        #expect(GatewayTurn.repliesToYou(in: history).isEmpty)
        // The routine's output is the news instead.
        #expect(GatewayTurn.news(in: history) == [history[0]])
    }

    @Test func aRoutineTheBotAnsweredIsNewsOnlyThroughTheReply() {
        let history = [
            HistoryMessage(
                role: "user", text: "[Cronjob \"ping\" output — x]\n\nNew leads", displayKind: "internal_notification"),
            HistoryMessage(role: "assistant", text: "Two new leads; I drafted replies."),
            HistoryMessage(role: "user", text: "Thanks"),
            HistoryMessage(role: "assistant", text: "[SILENT]"),
        ]
        #expect(GatewayTurn.news(in: history) == [history[1]])
    }

    @Test func theSidebarDoesntShowIt() {
        #expect(Contact.plainPreview("[SILENT]").isEmpty)
    }
}
