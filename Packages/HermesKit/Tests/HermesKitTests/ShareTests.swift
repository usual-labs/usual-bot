import Foundation
import Testing
import UniformTypeIdentifiers

@testable import HermesKit

struct SharedContentTests {
    @Test func aFileWinsOverALinkOrTextAndALinkOverText() {
        // Photos, Files and a text file from Files arrive as files.
        #expect(SharedContent.kind(of: [.heic, .jpeg]) == .file(.heic))
        #expect(SharedContent.kind(of: [.pdf, .fileURL]) == .file(.pdf))
        #expect(SharedContent.kind(of: [.plainText, .fileURL]) == .file(.plainText))
        #expect(SharedContent.kind(of: [.fileURL]) == .file(.data))
        // Safari offers a page as a link; a selection in Notes offers rich and plain text.
        #expect(SharedContent.kind(of: [.url]) == .link)
        #expect(SharedContent.kind(of: [.url, .plainText]) == .link)
        #expect(SharedContent.kind(of: [.rtf, .plainText]) == .text)
        #expect(SharedContent.kind(of: [.contact]) == .unsupported)
        #expect(SharedContent.kind(of: []) == .unsupported)
    }

    @Test func filesOverTheAppsLimitsAreLeftOutWithTheReason() {
        let megabyte = 1024 * 1024
        var content = SharedContent()
        content.add(.init(name: "cat.png", url: URL(filePath: "/tmp/cat.png"), size: 25 * megabyte))
        content.add(.init(name: "IMG_1.HEIC", url: URL(filePath: "/tmp/IMG_1.HEIC"), size: 31 * megabyte))
        content.add(.init(name: "report.pdf", url: URL(filePath: "/tmp/report.pdf"), size: 50 * megabyte))
        content.add(.init(name: "clip.mov", url: URL(filePath: "/tmp/clip.mov"), size: 50 * megabyte + 1))

        #expect(content.files.map(\.name) == ["cat.png", "report.pdf"])
        #expect(
            content.problems == [
                "IMG_1.HEIC is 31 MB, so it's left out. Images can be up to 25 MB.",
                "clip.mov is 51 MB, so it's left out. Files can be up to 50 MB.",
            ])
        #expect(content.summary == "1 image and 1 file")
    }

    @Test func theMessageIsYourNoteThenTheTextThenLinksItDoesNotAlreadyName() throws {
        var content = SharedContent()
        #expect(content.isEmpty)
        content.addText("  Worth a read  ")
        content.addText("Worth a read")
        content.addText("   ")
        content.addLink(try #require(URL(string: "https://example.com/post")))
        content.addLink(try #require(URL(string: "https://example.com/post")))
        #expect(
            content.message(note: " Summarise this\n") == "Summarise this\n\nWorth a read\n\nhttps://example.com/post")

        var quoted = SharedContent()
        quoted.addText("See https://example.com/post for more")
        quoted.addLink(try #require(URL(string: "https://example.com/post")))
        #expect(quoted.message(note: "") == "See https://example.com/post for more")
        #expect(content.summary == "example.com and text")
    }

    @Test func roomsTakeTextAndLinksOnly() throws {
        let room = Contact(id: "room:r1", name: "Launch room", kind: .room(memberIDs: ["writer"]))
        let bot = Contact(id: "writer", name: "Writer")
        var content = SharedContent()
        content.addLink(try #require(URL(string: "https://example.com")))
        #expect(content.problem(sendingTo: room) == nil)
        content.add(.init(name: "cat.png", url: URL(filePath: "/tmp/cat.png"), size: 4))
        #expect(content.problem(sendingTo: room) == "Rooms take text and links only. Pick a Bot to send files.")
        #expect(content.problem(sendingTo: bot) == nil)
    }
}

/// A shared folder in a temporary directory, with a file to share.
struct ShareFolder {
    let root = FileManager.default.temporaryDirectory.appending(path: "usualbot-share-\(UUID().uuidString)")
    var container: ShareContainer { ShareContainer(directory: root.appending(path: "Share")) }

    func file(_ name: String, _ data: Data) throws -> SharedContent.File {
        let folder = root.appending(path: "incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try data.write(to: url)
        return SharedContent.File(name: name, url: url, size: data.count)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

struct ShareContainerTests {
    private let forge = Contact(id: "forge", name: "Forge")

    @Test func whatYouShareWaitsInTheFolderWithItsFiles() throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let container = folder.container
        #expect(container.items().isEmpty)
        #expect(container.lastContactID == nil)

        var content = SharedContent()
        content.addText("Two photos")
        content.add(try folder.file("IMG.jpg", Data("one".utf8)))
        content.add(try folder.file("IMG.jpg", Data("two".utf8)))
        content.add(try folder.file("item.json", Data("{}".utf8)))
        let item = try container.add(content, note: "Which is better?", to: forge, gateway: "g1")

        #expect(container.items() == [item])
        #expect(item.text == "Which is better?\n\nTwo photos")
        #expect(item.files == ["IMG.jpg", "IMG 2.jpg", "item 2.json"])
        #expect(item.failure == nil)
        #expect(try Data(contentsOf: container.fileURL("IMG 2.jpg", of: item)) == Data("two".utf8))
        #expect(container.lastContactID == "forge")

        container.remove(item.id)
        #expect(container.items().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: container.fileURL("IMG.jpg", of: item).path))
    }

    @Test func aFileThatCannotBeCopiedLeavesNothingBehind() throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        var content = SharedContent()
        content.add(.init(name: "gone.pdf", url: folder.root.appending(path: "gone.pdf"), size: 3))
        #expect(throws: (any Error).self) {
            try folder.container.add(content, note: "", to: forge, gateway: "g1")
        }
        #expect(folder.container.items().isEmpty)
    }

    @Test func theRosterIsReadBackAndGoesWithEverythingElseOnClear() throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let container = folder.container
        #expect(container.roster() == nil)
        let room = Contact(id: "room:r1", name: "Launch room", kind: .room(memberIDs: ["forge", "courier"]))
        let roster = ShareRoster(
            gateway: "g1", contacts: [forge, room], hidden: [Contact(id: "courier", name: "Courier")],
            pictures: ["forge": Data([1, 2, 3])])
        try container.write(roster)
        var content = SharedContent()
        content.addText("Hello")
        try container.add(content, note: "", to: forge, gateway: "g1")

        #expect(container.roster() == roster)
        #expect(roster.members(of: room).map(\.id) == ["forge", "courier"])

        container.clear()
        #expect(container.roster() == nil)
        #expect(container.items().isEmpty)
        #expect(container.lastContactID == nil)
    }
}

@MainActor
struct SharedSendingTests {
    private let hermes = Contact(id: "hermes", name: "Hermes", chatID: "stored-1")

    /// A signed-in model at the front and online, with a shared folder, and the gateway its chats talk to.
    private func model(_ folder: ShareFolder) async throws -> (AppModel, ScriptedGateway) {
        let store = MemoryTokenStore()
        try store.save(
            TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            for: testGateway)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let model = AppModel(
            tokenStore: store, http: ScriptedHTTP { _ in (200, "{}") }, defaults: defaults,
            cache: OfflineCache(directory: folder.root.appending(path: "cache")), share: folder.container,
            makeSocket: { _ in FakeSocket() })
        // In the background, so the model doesn't dial; the test stands in for the link.
        model.setForeground(false)
        await model.restore()
        model.isForeground = true
        let gateway = ScriptedGateway()
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        model.channel = channel
        model.link = .online(.legacy)
        model.rosterReads = 1
        model.contacts = [hermes]
        return (model, gateway)
    }

    /// Opens the chat with Hermes; the gateway's request 0 is the resume.
    private func openChat(_ model: AppModel, _ gateway: ScriptedGateway) async throws -> ChatThread {
        let thread = model.thread(for: hermes)
        model.openThread(for: hermes)
        _ = try await gateway.answer(
            0, method: "session.resume", result: ["session_id": "live-1", "running": false, "messages": .array([])])
        try await waitUntilOnMain { thread.isAttached }
        return thread
    }

    private func share(
        _ folder: ShareFolder, text: String = "", files: [SharedContent.File] = [], to contact: Contact
    ) throws -> SharedItem {
        var content = SharedContent()
        content.addText(text)
        for file in files { content.add(file) }
        return try folder.container.add(content, note: "", to: contact, gateway: testGateway.fileName)
    }

    @Test func aSharedLinkAndFileGoToTheChatAndLeaveTheFolder() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let (model, gateway) = try await model(folder)
        let thread = try await openChat(model, gateway)
        let pdf = try folder.file("report.pdf", Data("%PDF".utf8))
        let item = try share(folder, text: "https://example.com/post", files: [pdf], to: hermes)

        let sending = Task { await model.sendShared() }
        let file = try await gateway.answer(
            1, method: "file.attach",
            result: ["attached": true, "ref_text": "@file:attachments/report.pdf", "name": "report.pdf"])
        #expect(
            file["data_url"]
                == .string("data:application/octet-stream;base64," + Data("%PDF".utf8).base64EncodedString()))
        // Until it's in the chat, the app shows it waiting.
        #expect(model.shared.items == [item])
        let submit = try await gateway.answer(2, method: "prompt.submit", result: ["status": "streaming"])
        await sending.value

        #expect(submit["text"] == "https://example.com/post\n\n@file:attachments/report.pdf")
        #expect(
            thread.state.items.map(\.content) == [.user("https://example.com/post\n\n@file:attachments/report.pdf")])
        #expect(model.shared.items.isEmpty)
        #expect(folder.container.items().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.container.fileURL("report.pdf", of: item).path))
    }

    @Test func aFailedUploadKeepsTheItemWithTheReasonAndTryAgainSendsIt() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let (model, gateway) = try await model(folder)
        _ = try await openChat(model, gateway)
        _ = try share(folder, files: [try folder.file("report.pdf", Data("%PDF".utf8))], to: hermes)

        let sending = Task { await model.sendShared() }
        _ = try await gateway.answer(1, method: "file.attach", error: (5028, "disk full"))
        await sending.value

        #expect(model.shared.items.map(\.failure) == ["Couldn't attach report.pdf: disk full"])
        // It's on disk too, so it's still there after a relaunch, and the next pass leaves it alone.
        #expect(folder.container.items().map(\.failure) == ["Couldn't attach report.pdf: disk full"])
        await model.sendShared()
        #expect(gateway.socket.sent.count == 2)

        let failed = try #require(model.shared.items.first)
        model.shared.retry(failed)
        #expect(model.shared.items.map(\.failure) == [nil])
        _ = try await gateway.answer(
            2, method: "file.attach",
            result: ["attached": true, "ref_text": "@file:attachments/report.pdf", "name": "report.pdf"])
        _ = try await gateway.answer(3, method: "prompt.submit", result: ["status": "streaming"])
        try await waitUntilOnMain { model.shared.items.isEmpty }
        #expect(folder.container.items().isEmpty)
    }

    @Test func anItemWaitsWhileTheBotIsAnsweringOrTheAppIsOffline() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let (model, gateway) = try await model(folder)
        let thread = try await openChat(model, gateway)
        let item = try share(folder, text: "Read this later", to: hermes)

        model.link = .offline("No connection")
        await model.sendShared()
        #expect(model.shared.items == [item])

        // A reply is running: sending now would steer it.
        model.link = .online(.legacy)
        thread.state.beginTurn()
        await model.sendShared()
        #expect(model.shared.items == [item])
        #expect(gateway.socket.sent.count == 1)

        thread.state.endTurnLocally()
        await model.sendShared()
        _ = try await gateway.answer(1, method: "prompt.submit", result: ["status": "streaming"])
        #expect(model.shared.items.isEmpty)
    }

    @Test func anItemForABotThatIsGoneOrAnotherGatewayIsNotSent() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let (model, gateway) = try await model(folder)
        _ = try share(folder, text: "Hello", to: Contact(id: "scout", name: "Scout"))
        var other = SharedContent()
        other.addText("For the demo")
        try folder.container.add(other, note: "", to: hermes, gateway: "another-gateway")

        await model.sendShared()

        #expect(model.shared.items.map(\.failure) == ["Scout isn't on this gateway any more."])
        #expect(folder.container.items().count == 2)
        #expect(gateway.socket.sent.isEmpty)

        // A Bot renamed on the gateway still gets what was shared under its old name.
        model.renamedAgents["scout"] = "hermes"
        _ = try await openChat(model, gateway)
        model.shared.retry(try #require(model.shared.items.first))
        let submit = try await gateway.answer(1, method: "prompt.submit", result: ["status": "streaming"])
        #expect(submit["text"] == "Hello")
    }

    @Test func aRoomTakesSharedTextAndRefusesFiles() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let (model, gateway) = try await model(folder)
        let row: JSONValue = [
            "room_id": "r1", "name": "Launch room",
            "members": [["member_id": "m-writer", "profile": "writer", "handle": "writer"]],
            "authority_gateway_id": "g1", "authority_epoch": 1, "revision": 3, "created_at": 1_792_700_000.0,
            "updated_at": 1_792_735_200.5, "idempotent": false, "latest_seq": 0,
        ]
        let summary = try #require(RoomSummary(row))
        let contact = Contact(room: summary)
        let room = RoomThread(summary: summary, channel: { [weak model] in model?.channel })
        model.contacts = [hermes, contact]
        model.rooms[contact.id] = room
        _ = try share(folder, text: "https://example.com/post", to: contact)
        _ = try share(folder, files: [try folder.file("cat.png", Data([1]))], to: contact)

        // The room is still loading: both wait.
        await model.sendShared()
        #expect(model.shared.items.map(\.failure) == [nil, "Rooms take text and links only. Share files to a Bot."])
        #expect(gateway.socket.sent.isEmpty)

        async let synced: Void = room.sync()
        _ = try await gateway.answer(0, method: "groups.log", result: ["events": [], "has_more": false])
        _ = try await gateway.answer(
            1, method: "groups.state", result: ["room": row, "driver_status": ["running": true]])
        await synced
        await model.sendShared()
        let sent = try await gateway.answer(2, method: "groups.send", result: ["accepted": true])

        #expect(sent["payload"]?["text"] == "https://example.com/post")
        #expect(room.pending.map(\.text) == ["https://example.com/post"])
        #expect(model.shared.items.count == 1)
    }

    @Test func thePickerGetsTheSidebarsContactsWithoutWhatWasSaid() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let (model, _) = try await model(folder)
        model.contacts = [
            Contact(id: "atlas", name: "Atlas", preview: "The deploy is done", lastActive: .now),
            Contact(
                id: "forge", name: "Forge", preview: "On it", isPinned: true, details: AgentDetails(profile: "forge")),
        ]
        model.hiddenBots = [Contact(id: "courier", name: "Courier", preview: "Sent")]

        model.publishShareRoster()

        let roster = try #require(folder.container.roster())
        #expect(roster.gateway == testGateway.fileName)
        #expect(
            roster.contacts == [
                Contact(id: "forge", name: "Forge", isPinned: true), Contact(id: "atlas", name: "Atlas"),
            ])
        #expect(roster.hidden == [Contact(id: "courier", name: "Courier")])
    }

    @Test func signingOutEmptiesTheSharedFolder() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let (model, _) = try await model(folder)
        model.publishShareRoster()
        _ = try share(folder, text: "Hello", to: hermes)
        model.link = .offline("No connection")
        await model.sendShared()
        #expect(model.shared.items.count == 1)

        model.signOut()

        #expect(model.shared.items.isEmpty)
        #expect(folder.container.roster() == nil)
        #expect(folder.container.items().isEmpty)
    }
}
