import CoreGraphics
import HermesKit
import Testing

@testable import UsualUI

struct SidebarDropRulesTests {
    private let work = ContactSection(id: "work", name: "Work")

    private func bot(_ id: String, section: ContactSection? = nil, pinned: Bool = false) -> Contact {
        Contact(id: id, name: id, isPinned: pinned, sectionID: section?.id, sectionName: section?.name)
    }

    /// Pinned "a" and "b" side by side in a strip at the top, then Work, then the rest.
    private func rules(grouped: Bool = true) -> (SidebarDropRules, a: Contact, b: Contact, c: Contact, d: Contact) {
        let a = bot("a", pinned: true)
        let b = bot("b", pinned: true)
        let c = bot("c", section: work)
        let d = bot("d")
        let blocks = SidebarBlock.blocks(for: [a, b, c, d], in: grouped ? [work] : [], pinOrder: ["a", "b"])
        let geometry = SidebarDragGeometry()
        geometry.pins = [
            "a": CGRect(x: 0, y: 0, width: 50, height: 60), "b": CGRect(x: 50, y: 0, width: 50, height: 60),
        ]
        for (index, block) in blocks.enumerated() {
            geometry.blocks[block.id] = CGRect(x: 0, y: CGFloat(index) * 100, width: 200, height: 90)
        }
        return (SidebarDropRules(blocks: blocks, isGrouped: grouped, geometry: geometry), a, b, c, d)
    }

    @Test func aPinnedChatTakesAnotherPinsPlaceButNotItsOwn() {
        let (rules, a, _, _, _) = rules()
        #expect(rules.target(for: a, at: CGPoint(x: 75, y: 30)) == .pin("b"))
        #expect(rules.target(for: a, at: CGPoint(x: 25, y: 30)) == nil)
        #expect(rules.target(for: a, at: CGPoint(x: 150, y: 30)) == nil)
    }

    @Test func aChatFromASectionCanBePinnedInAPlaceOrLast() {
        let (rules, _, _, c, _) = rules()
        #expect(rules.target(for: c, at: CGPoint(x: 25, y: 30)) == .pin("a"))
        #expect(rules.target(for: c, at: CGPoint(x: 150, y: 30)) == .block(SidebarBlock.pinnedID))
    }

    @Test func aChatGoesToASectionAndAPinnedOneLeavesThePins() {
        let (rules, a, _, c, d) = rules()
        #expect(rules.target(for: d, at: CGPoint(x: 10, y: 150)) == .block("work"))
        #expect(rules.target(for: a, at: CGPoint(x: 10, y: 150)) == .block("work"))
        #expect(rules.target(for: c, at: CGPoint(x: 10, y: 250)) == .block(SidebarBlock.unassignedID))
        #expect(rules.target(for: c, at: CGPoint(x: 10, y: 95)) == nil)
    }

    @Test func withoutSectionsOnlyAPinnedChatHasSomewhereToGoInTheList() {
        let (rules, a, _, _, d) = rules(grouped: false)
        #expect(rules.target(for: d, at: CGPoint(x: 10, y: 150)) == nil)
        #expect(rules.target(for: a, at: CGPoint(x: 10, y: 150)) == .block(SidebarBlock.unassignedID))
        #expect(rules.target(for: d, at: CGPoint(x: 25, y: 30)) == .pin("a"))
    }
}
