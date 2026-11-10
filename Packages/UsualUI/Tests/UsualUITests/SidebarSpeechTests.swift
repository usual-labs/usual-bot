import HermesKit
import Testing

@testable import UsualUI

struct SidebarSpeechTests {
    private let forge = Contact(id: "forge", name: "Forge", unreadCount: 2, activity: .needsYou)
    private let atlas = Contact(id: "atlas", name: "Atlas", unreadCount: 3)
    private let ops = Contact(id: "ops", name: "Ops", activity: .working)

    @Test func aRowSaysWhetherItNeedsYouOrIsWorkingAndWhatsUnread() {
        #expect(
            SidebarSpeech.row(forge, preview: "Needs your OK", stamp: nil)
                == "Forge, needs you, 2 unread, Needs your OK")
        #expect(SidebarSpeech.row(ops, preview: "Checking", stamp: "10:44 AM") == "Ops, working, Checking, 10:44 AM")
        #expect(SidebarSpeech.row(Contact(id: "a", name: "Scribe"), preview: "", stamp: nil) == "Scribe")
    }

    @Test func aPinnedChatSaysSo() {
        let pinned = Contact(id: "atlas", name: "Atlas", unreadCount: 3, isPinned: true)
        #expect(SidebarSpeech.row(pinned, preview: "", stamp: nil) == "Atlas, pinned, 3 unread")
    }

    @Test func aFoldedSectionSaysWhatItsHiddenRowsWould() {
        let block = SidebarBlock(section: nil, contacts: [forge, atlas, ops])
        #expect(SidebarSpeech.section(block, isFolded: true) == "Folded, needs you, 5 unread")
        #expect(SidebarSpeech.section(SidebarBlock(section: nil, contacts: [ops]), isFolded: true) == "Folded")
        #expect(SidebarSpeech.section(block, isFolded: false) == "Open")
    }
}

struct MachineRowTests {
    @Test func theMachineRowSaysWhenTheBotIsWaitingOnYou() {
        #expect(Contact.Activity.needsYou.label == "Needs you")
        #expect(Contact.Activity.working.label == "Working")
        #expect(Contact.Activity.idle.label == "Idle")
    }
}
