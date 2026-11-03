import HermesKit
import Testing

@testable import UsualUI

@MainActor
struct DeleteBotSheetTests {
    private func forge(_ activity: Contact.Activity) -> Contact {
        var contact = Contact(id: "forge", name: "Forge")
        contact.activity = activity
        return contact
    }

    @Test func saysNothingAboutAnIdleBot() {
        #expect(DeleteBotSheet.activityNote(for: forge(.idle)) == nil)
    }

    @Test func saysAReplyStopsWhileItWorks() {
        #expect(
            DeleteBotSheet.activityNote(for: forge(.working))
                == "Forge is in the middle of a reply. Deleting it stops that.")
    }

    /// Waiting for your OK isn't a reply under way.
    @Test func saysItWaitsOnYouWhenItNeedsYou() {
        #expect(
            DeleteBotSheet.activityNote(for: forge(.needsYou))
                == "Forge is waiting on you. Deleting it drops that request.")
    }
}
