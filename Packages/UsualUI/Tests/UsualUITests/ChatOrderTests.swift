import HermesKit
import Testing

@testable import UsualUI

struct ChatOrderTests {
    private let forge = Contact(id: "forge", name: "Forge")
    private let atlas = Contact(id: "atlas", name: "Atlas")
    private let ops = Contact(id: "ops", name: "Ops")
    private let crew = Contact(id: "room:crew", name: "Launch crew", kind: .room(memberIDs: ["forge", "atlas"]))

    private var blocks: [SidebarBlock] {
        [
            SidebarBlock(section: ContactSection(id: "product", name: "Product"), contacts: [forge, atlas]),
            SidebarBlock(section: ContactSection(id: "back", name: "Back office"), contacts: [ops]),
            SidebarBlock(section: nil, contacts: [crew]),
        ]
    }

    @Test func nextAndPreviousFollowTheSidebarAndWrap() {
        let ids = ChatOrder.shown(blocks, isFolded: { _ in false }).map(\.id)
        #expect(ids == ["forge", "atlas", "ops", "room:crew"])
        #expect(ChatOrder.step(from: "atlas", by: 1, in: ids) == "ops")
        #expect(ChatOrder.step(from: "room:crew", by: 1, in: ids) == "forge")
        #expect(ChatOrder.step(from: "forge", by: -1, in: ids) == "room:crew")
    }

    @Test func foldedSectionsAreSkipped() {
        let ids = ChatOrder.shown(blocks, isFolded: { $0 == "back" }).map(\.id)
        #expect(ids == ["forge", "atlas", "room:crew"])
        #expect(ChatOrder.step(from: "atlas", by: 1, in: ids) == "room:crew")
    }

    @Test func withNoChatOpenNextIsTheFirstAndPreviousTheLast() {
        let ids = ["forge", "atlas", "ops"]
        #expect(ChatOrder.step(from: nil, by: 1, in: ids) == "forge")
        #expect(ChatOrder.step(from: nil, by: -1, in: ids) == "ops")
        // A chat in a folded section counts as none open.
        #expect(ChatOrder.step(from: "hidden", by: 1, in: ids) == "forge")
        #expect(ChatOrder.step(from: nil, by: 1, in: []) == nil)
    }
}
