import Foundation
import Testing

@testable import HermesKit

struct BotMetaWriteTests {
    private func channel(_ gateway: ScriptedGateway) async -> JSONRPCChannel {
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        return channel
    }

    private func list(meta: JSONValue, revision: Int?) -> JSONValue {
        var row: [String: JSONValue] = ["name": "scout", "ui_meta": ["hermes-bots": meta]]
        if let revision { row["ui_meta_revisions"] = ["hermes-bots": .number(Double(revision))] }
        return ["profiles": .array([["name": "other"], .object(row)])]
    }

    private let saved: JSONValue = ["ok": true, "applied": ["ui_meta": true]]
    private let work = ContactPlacement(id: "sec-1", name: "Work")

    @Test func aMoveKeepsEverythingElseOnTheBot() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let write: Void = BotMetaWrite.setSection(work, profile: "scout", on: channel)

        let read = try await gateway.answer(
            0, method: "profiles.list",
            result: list(meta: ["title": "Scout", "pinned": true, "future": ["kept": 1], "chat": "gone"], revision: 7))
        #expect(read == ["include_sessions": false])
        let sent = try await gateway.answer(1, method: "profiles.configure", result: saved)
        try await write
        #expect(sent["name"] == "scout")
        #expect(sent["ui_meta_expected_revisions"] == ["hermes-bots": 7])
        #expect(
            sent["ui_meta"]?["hermes-bots"]
                == [
                    "title": "Scout", "pinned": true, "future": ["kept": 1], "sectionId": "sec-1",
                    "sectionName": "Work",
                ])
    }

    @Test func takingABotOutSendsNulls() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let write: Void = BotMetaWrite.setSection(
            ContactPlacement(id: nil, name: nil), profile: "scout", on: channel)

        _ = try await gateway.answer(
            0, method: "profiles.list", result: list(meta: ["sectionId": "sec-1"], revision: 1))
        let sent = try await gateway.answer(1, method: "profiles.configure", result: saved)
        try await write
        #expect(sent["ui_meta"]?["hermes-bots"] == ["sectionId": .null, "sectionName": .null])
    }

    @Test func aBotWithNoStoredRevisionExpectsZero() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let write: Void = BotMetaWrite.setSection(work, profile: "scout", on: channel)

        let row: JSONValue = ["name": "scout", "ui_meta_revisions": [:]]
        _ = try await gateway.answer(0, method: "profiles.list", result: ["profiles": .array([row])])
        let sent = try await gateway.answer(1, method: "profiles.configure", result: saved)
        try await write
        #expect(sent["ui_meta_expected_revisions"] == ["hermes-bots": 0])
    }

    @Test func anOlderGatewayIsWrittenWithoutARevision() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let write: Void = BotMetaWrite.setSection(work, profile: "scout", on: channel)

        _ = try await gateway.answer(0, method: "profiles.list", result: list(meta: [:], revision: nil))
        let sent = try await gateway.answer(1, method: "profiles.configure", result: saved)
        try await write
        #expect(sent["ui_meta_expected_revisions"] == nil)
    }

    @Test func aConflictReadsAgainAndKeepsTheOtherWrite() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let write: Void = BotMetaWrite.setSection(work, profile: "scout", on: channel)

        _ = try await gateway.answer(0, method: "profiles.list", result: list(meta: [:], revision: 1))
        _ = try await gateway.answer(
            1, method: "profiles.configure",
            result: [
                "applied": ["ui_meta": false, "ui_meta_conflicts": ["hermes-bots": ["expected": 1, "actual": 2]]]
            ])
        _ = try await gateway.answer(2, method: "profiles.list", result: list(meta: ["title": "New"], revision: 2))
        let sent = try await gateway.answer(3, method: "profiles.configure", result: saved)
        try await write
        #expect(sent["ui_meta_expected_revisions"] == ["hermes-bots": 2])
        #expect(sent["ui_meta"]?["hermes-bots"]?["title"] == "New")
    }

    @Test func aWriteTheGatewayIgnoredIsAFailure() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        let write = Task { [work] in try await BotMetaWrite.setSection(work, profile: "scout", on: channel) }

        _ = try await gateway.answer(0, method: "profiles.list", result: list(meta: [:], revision: 1))
        _ = try await gateway.answer(1, method: "profiles.configure", result: ["ok": true])
        await #expect(throws: GatewayError.self) { try await write.value }
    }

    @Test func aSectionReadsFromTheRoster() throws {
        let list: JSONValue = [
            "profiles": .array([
                ["name": "a", "ui_meta": ["hermes-bots": ["sectionId": "sec-1", "sectionName": " Work "]]],
                ["name": "b", "ui_meta": ["hermes-bots": ["sectionId": .null, "sectionName": .null]]],
            ])
        ]
        let contacts = try list.decode(ProfileList.self).profiles.compactMap(Contact.init(profile:))
        #expect(contacts[0].sectionID == "sec-1")
        #expect(contacts[0].sectionName == "Work")
        #expect(contacts[1].sectionID == nil)
    }
}

@MainActor
struct SidebarSectionsTests {
    /// Remembers what was saved, and fails while `failing` is set.
    @MainActor
    final class Saver {
        var saved: [(profile: String, placement: ContactPlacement)] = []
        var failing = false

        func save(_ profile: String, _ placement: ContactPlacement) async throws {
            if failing { throw GatewayError.disconnected }
            saved.append((profile, placement))
        }
    }

    private let saver = Saver()
    private let defaults = UserDefaults(suiteName: "SectionTests-\(UUID().uuidString)")!
    private let gateway = try! GatewayAddress(parsing: "https://hermes.example.com")
    private let work = ContactSection(id: "sec-1", name: "Work")

    private func store() -> SidebarSections {
        SidebarSections(defaults: defaults, save: { [saver] in try await saver.save($0, $1) })
    }

    private func bot(_ id: String, section: ContactSection? = nil, active minutes: Double = 0) -> Contact {
        Contact(
            id: id, name: id, lastActive: Date(timeIntervalSince1970: 1000 - minutes * 60),
            details: AgentDetails(profile: id), sectionID: section?.id, sectionName: section?.name)
    }

    private var room: Contact { Contact(id: "room-1", name: "Room", kind: .room(memberIDs: [])) }

    @Test func noSectionsMeansOneBlock() {
        let blocks = store().blocks(for: [bot("a"), bot("b")])
        #expect(blocks.map(\.section) == [nil])
        #expect(blocks[0].contacts.count == 2)
    }

    @Test func blocksKeepRosterOrderAndFileTheRestLast() {
        let sections = store()
        sections.reconcile([bot("a", section: work)])
        let lost = ContactSection(id: "sec-lost", name: "")
        let blocks = sections.blocks(for: [
            bot("old", section: work, active: 9), bot("new", section: work), bot("free"),
            Contact(id: "lost", name: "lost", sectionID: lost.id),
        ])
        #expect(blocks.map(\.id) == ["sec-1", SidebarBlock.unassignedID])
        #expect(blocks[0].contacts.map(\.id) == ["new", "old"])
        #expect(blocks[1].contacts.map(\.id) == ["free", "lost"])
    }

    @Test func nothingLeftOverMeansNoUnassigned() {
        let sections = store()
        sections.reconcile([bot("a", section: work)])
        #expect(sections.blocks(for: [bot("a", section: work)]).map(\.id) == ["sec-1"])
    }

    @Test func aMoveShowsAtOnceAndSurvivesAStaleRead() async {
        let sections = store()
        sections.reconcile([bot("a", section: work), bot("b")])
        sections.move(bot("b"), to: work)
        #expect(sections.placed(bot("b")).sectionID == work.id)
        await sections.writesFinished()
        #expect(saver.saved.map(\.profile) == ["b"])
        #expect(saver.saved.first?.placement == ContactPlacement(id: work.id, name: work.name))

        // This read started before the write landed.
        sections.reconcile([bot("a", section: work), bot("b")])
        #expect(sections.placed(bot("b")).sectionID == work.id)
    }

    @Test func aMoveMadeElsewhereWinsOnceTheRosterIsFresh() async {
        let sections = store()
        sections.reconcile([bot("b")])
        sections.create(moving: bot("b"))
        await sections.writesFinished()
        sections.reconcile([bot("b")])
        sections.reconcile([bot("b")])
        #expect(sections.placed(bot("b")).sectionID == nil)
    }

    @Test func aFailedMoveGoesBackAndSaysWhy() async {
        let sections = store()
        sections.reconcile([bot("a", section: work), bot("b")])
        saver.failing = true
        sections.move(bot("b"), to: work)
        await sections.writesFinished()
        #expect(sections.placed(bot("b")).sectionID == nil)
        #expect(sections.problem != nil)
    }

    @Test func aMoveHoldsWhileWritesAreStillRunning() async {
        let sections = store()
        sections.reconcile([bot("a", section: work), bot("b")])
        sections.move(bot("b"), to: work)
        sections.reconcile([bot("a", section: work), bot("b")])
        sections.reconcile([bot("a", section: work), bot("b")])
        #expect(sections.placed(bot("b")).sectionID == work.id)
        await sections.writesFinished()
    }

    @Test func aSectionFromElsewhereIsRebuiltFromItsBots() {
        let sections = store()
        sections.reconcile([bot("a", section: work), Contact(id: "b", name: "b", sectionID: "sec-nameless")])
        #expect(sections.sections == [work])
    }

    @Test func aNameIsTakenOnlyWhenEveryBotAgrees() {
        let renamed = ContactSection(id: work.id, name: "Studio")
        let agreed = SidebarSections.adopting([bot("a", section: renamed), bot("b", section: renamed)], into: [work])
        #expect(agreed == [renamed])
        let mixed = SidebarSections.adopting([bot("a", section: renamed), bot("b", section: work)], into: [work])
        #expect(mixed == [work])
    }

    @Test func aRenameReachesItsBotsAndSticks() async {
        let sections = store()
        let contacts = [bot("a", section: work), bot("b", section: work), bot("c")]
        sections.reconcile(contacts)
        sections.rename(work, to: "  Studio ", contacts: contacts)
        // Mid-rename the roster still has the old name on every Bot.
        sections.reconcile(contacts)
        #expect(sections.sections.map(\.name) == ["Studio"])
        await sections.writesFinished()
        #expect(saver.saved.map(\.profile) == ["a", "b"])
        #expect(saver.saved.allSatisfy { $0.placement.name == "Studio" })
    }

    @Test func aBlankNameKeepsTheOldOne() {
        let sections = store()
        sections.reconcile([bot("a", section: work)])
        sections.rename(work, to: "  ", contacts: [bot("a", section: work)])
        #expect(sections.sections == [work])
        #expect(saver.saved.isEmpty)
    }

    @Test func aDeletedSectionStaysGoneWhileItsBotsSave() async {
        let sections = store()
        let contacts = [bot("a", section: work)]
        sections.reconcile(contacts)
        sections.delete(work, contacts: contacts)
        sections.reconcile(contacts)
        #expect(sections.sections.isEmpty)
        await sections.writesFinished()
        #expect(saver.saved.first?.placement == ContactPlacement(id: nil, name: nil))
    }

    @Test func aDeleteThatCantSaveBringsTheSectionBack() async {
        let sections = store()
        let contacts = [bot("a", section: work)]
        sections.reconcile(contacts)
        saver.failing = true
        sections.delete(work, contacts: contacts)
        await sections.writesFinished()
        sections.reconcile(contacts)
        #expect(sections.sections == [work])
        #expect(sections.problem != nil)
    }

    @Test func aRoomStaysOnThisDevice() async {
        let sections = store()
        sections.reconcile([bot("a", section: work)])
        sections.move(room, to: work)
        await sections.writesFinished()
        #expect(saver.saved.isEmpty)
        #expect(sections.placed(room).sectionID == work.id)
        sections.delete(work, contacts: [sections.placed(room)])
        #expect(sections.placed(room).sectionID == nil)
    }

    @Test func aNewSectionIsMadeAroundItsFirstBot() async {
        let sections = store()
        let section = sections.create(moving: bot("a"))
        #expect(section.id.hasPrefix("sec-"))
        #expect(section.name == "New section")
        #expect(sections.sections == [section])
        #expect(sections.placed(bot("a")).sectionID == section.id)
        await sections.writesFinished()
    }

    @Test func sectionsMoveAndStopAtTheEnds() {
        let sections = store()
        let other = ContactSection(id: "sec-2", name: "Home")
        sections.reconcile([bot("a", section: work), bot("b", section: other)])
        sections.shift(other, by: -1)
        #expect(sections.sections.map(\.id) == ["sec-2", "sec-1"])
        sections.shift(other, by: -1)
        #expect(sections.sections.map(\.id) == ["sec-2", "sec-1"])
    }

    @Test func thisDevicesChoicesComeBackPerGateway() async throws {
        let first = store()
        first.load(for: gateway)
        first.reconcile([bot("a", section: work)])
        first.toggleFolded(work.id)
        first.move(room, to: work)

        let second = store()
        second.load(for: gateway)
        #expect(second.sections == [work])
        #expect(second.isFolded(work.id))
        #expect(second.placed(room).sectionID == work.id)

        let elsewhere = store()
        elsewhere.load(for: try GatewayAddress(parsing: "https://elsewhere.example.com"))
        #expect(elsewhere.sections.isEmpty)
    }

    @Test func signingOutForgetsThem() {
        let sections = store()
        sections.load(for: gateway)
        sections.reconcile([bot("a", section: work)])
        sections.clear()
        #expect(sections.sections.isEmpty)

        let next = store()
        next.load(for: gateway)
        #expect(next.sections.isEmpty)
    }

    @Test func aFoldedBlockAddsUpWhatItHides() {
        var waiting = bot("a", section: work)
        waiting.activity = .needsYou
        var unread = bot("b", section: work)
        unread.unreadCount = 3
        let block = SidebarBlock(section: work, contacts: [waiting, unread])
        #expect(block.needsYou)
        #expect(block.unreadCount == 3)
    }
}
