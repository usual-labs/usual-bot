import Testing

@testable import HermesKit
@testable import UsualUI

struct TranscriptAnnouncementTests {
    @Test func aFoundMessageIsReadAsPlainWords() {
        let reply = TranscriptItem(id: 3, content: .assistant("**Turbopuffer** fits best.\nMEDIA:/tmp/chart.png"))
        #expect(TranscriptAnnouncement.found(reply) == "Found: Turbopuffer fits best.")
        let yours = TranscriptItem(
            id: 4, content: .user("> Atlas: Earlier\n\nYes, keep the fallback.\n\n@file:/tmp/a.md"))
        #expect(TranscriptAnnouncement.found(yours) == "Found: Yes, keep the fallback.")
        let long = TranscriptItem(
            id: 6, content: .assistant("## Review 12\n\n- " + String(repeating: "word ", count: 60)))
        let said = TranscriptAnnouncement.found(long)
        #expect(said.hasPrefix("Found: Review 12 word word"))
        #expect(said.count < 140)
        #expect(
            TranscriptAnnouncement.found(TranscriptItem(id: 5, content: .notice("Reconnected"))) == "Found the message")
    }

    @Test func aCardThatAppearsIsSaidOnceByWhatItAsks() {
        let none = WaitingCards()
        #expect(TranscriptAnnouncement.appeared(from: none, to: none, agent: "Forge") == nil)
        let approval = WaitingCards(approvals: 1)
        #expect(
            TranscriptAnnouncement.appeared(from: none, to: approval, agent: "Forge")
                == "Forge wants your OK to run a command")
        #expect(TranscriptAnnouncement.appeared(from: approval, to: approval, agent: "Forge") == nil)
        // Answering one isn't news.
        #expect(TranscriptAnnouncement.appeared(from: approval, to: none, agent: "Forge") == nil)
        let both = WaitingCards(approvals: 1, questions: 1)
        #expect(
            TranscriptAnnouncement.appeared(from: approval, to: both, agent: "Atlas") == "Atlas has a question for you")
        #expect(
            TranscriptAnnouncement.appeared(from: none, to: WaitingCards(secrets: 1), agent: "Ops")
                == "Ops needs a secret")
        #expect(
            TranscriptAnnouncement.appeared(from: none, to: WaitingCards(vault: 1), agent: "Ops")
                == "Ops needs a password, login or code")
        #expect(
            TranscriptAnnouncement.appeared(from: none, to: WaitingCards(connections: 1), agent: "Atlas")
                == "Atlas wants you to connect apps")
    }
}
