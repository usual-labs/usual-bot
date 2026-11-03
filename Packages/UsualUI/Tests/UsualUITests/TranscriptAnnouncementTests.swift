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
        #expect(
            TranscriptAnnouncement.found(TranscriptItem(id: 5, content: .notice("Reconnected"))) == "Found the message")
    }
}
