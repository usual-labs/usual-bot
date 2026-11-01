import Testing

@testable import HermesKit
@testable import UsualUI

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
}
