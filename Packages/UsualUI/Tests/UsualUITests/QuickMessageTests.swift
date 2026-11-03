import Testing

@testable import HermesKit
@testable import UsualUI

@MainActor
struct QuickMessageTests {
    @Test func tabCyclesRecipientsAndWraps() {
        let ids = ["hermes", "scout", "room:r1"]
        #expect(QuickMessageView.cycle(ids, from: "hermes", by: 1) == "scout")
        #expect(QuickMessageView.cycle(ids, from: "room:r1", by: 1) == "hermes")
        #expect(QuickMessageView.cycle(ids, from: "hermes", by: -1) == "room:r1")
        // Someone no longer listed: start from the first.
        #expect(QuickMessageView.cycle(ids, from: "gone", by: 1) == "scout")
        #expect(QuickMessageView.cycle([], from: nil, by: 1) == nil)
    }

    @Test func secretsAndSudoPasswordsGetTheirOwnTitles() {
        let secret = SecretPrompt(id: "1", sessionID: "s", kind: .secret(name: "KEY", message: "**Key?**"))
        #expect(SecretCard.title(secret, agentName: "Ops") == "Ops needs a secret")
        let sudo = SecretPrompt(id: "2", sessionID: "s", kind: .sudo(command: "sudo ls"))
        #expect(SecretCard.title(sudo, agentName: "Ops") == "Ops needs your sudo password")
    }

    @Test func waitingOnYouListsRoomRetriesAndAppConnections() {
        let model = AppModel.demo()
        let rows = WaitingOnYou.rows(model: model, contacts: model.sidebarContacts)
        let retry = rows.first { $0.id == "demo-retry" }
        #expect(retry?.title == "A reply in Launch crew didn't finish")
        if case .retry = retry?.action {} else { Issue.record("A stopped room reply should offer Try Again") }
        let connect = rows.first { $0.id == "demo-connect" }
        #expect(connect?.title == "Atlas wants to connect Notion and Google Drive")
        if case .open = connect?.action {} else { Issue.record("A connection request should open its chat") }
    }

    @Test func aQuickMessageWaitsForItsChatOrSaysWhyItCant() {
        #expect(QuickSend.readiness(canSend: true, link: .online(.legacy), failure: nil) == .ready)
        #expect(QuickSend.readiness(canSend: false, link: .online(.legacy), failure: nil) == .opening)
        #expect(QuickSend.readiness(canSend: false, link: .connecting, failure: nil) == .opening)
        #expect(
            QuickSend.readiness(canSend: false, link: .offline("No route to host"), failure: nil)
                == .blocked("You're offline, so this didn't send. Send it again once Usual Bot reconnects."))
        #expect(
            QuickSend.readiness(canSend: false, link: .online(.legacy), failure: "Chat isn't supported yet.")
                == .blocked("Chat isn't supported yet."))
        #expect(
            QuickSend.readiness(canSend: false, link: .online(.legacy), failure: nil, roomServiceStopped: true)
                == .blocked("The gateway's room service isn't running, so agents won't answer."))
    }
}
