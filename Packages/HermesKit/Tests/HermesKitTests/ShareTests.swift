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
    }

    @Test func theMessageIsTheTextThenLinksItDoesNotAlreadyName() throws {
        var content = SharedContent()
        #expect(content.isEmpty)
        content.addText("  Worth a read  ")
        content.addText("Worth a read")
        content.addText("   ")
        content.addLink(try #require(URL(string: "https://example.com/post")))
        content.addLink(try #require(URL(string: "https://example.com/post")))
        #expect(content.message == "Worth a read\n\nhttps://example.com/post")

        var quoted = SharedContent()
        quoted.addText("See https://example.com/post for more")
        quoted.addLink(try #require(URL(string: "https://example.com/post")))
        #expect(quoted.message == "See https://example.com/post for more")
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
    @Test func whatYouShareWaitsInTheFolderWithItsFiles() throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let container = folder.container
        #expect(container.items().isEmpty)

        var content = SharedContent()
        content.addText("Two photos")
        content.add(try folder.file("IMG.jpg", Data("one".utf8)))
        content.add(try folder.file("IMG.jpg", Data("two".utf8)))
        content.add(try folder.file("item.json", Data("{}".utf8)))
        content.problems = ["clip.mov is 51 MB, so it's left out. Files can be up to 50 MB."]
        let item = try container.add(content)

        #expect(container.items() == [item])
        #expect(item.text == "Two photos")
        #expect(item.files == ["IMG.jpg", "IMG 2.jpg", "item 2.json"])
        #expect(item.problems == content.problems)
        #expect(try Data(contentsOf: container.fileURL("IMG 2.jpg", of: item)) == Data("two".utf8))

        container.remove(item.id)
        #expect(container.items().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: container.fileURL("IMG.jpg", of: item).path))
    }

    @Test func aFileThatCannotBeCopiedLeavesNothingBehind() throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        var content = SharedContent()
        content.add(.init(name: "gone.pdf", url: folder.root.appending(path: "gone.pdf"), size: 3))
        #expect(throws: (any Error).self) { try folder.container.add(content) }
        #expect(folder.container.items().isEmpty)
    }

    /// An item an earlier version saved for a chat it had picked still opens, to be put in one.
    @Test func anItemFromAnEarlierVersionStillReads() throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let id = UUID()
        let itemFolder = folder.container.directory.appending(path: "Items/\(id.uuidString)")
        try FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)
        let old = """
            {"id":"\(id.uuidString)","gateway":"g1","contactID":"forge","contactName":"Forge",
            "text":"Hello","files":[],"created":0}
            """
        try Data(old.utf8).write(to: itemFolder.appending(path: "item.json"))
        #expect(folder.container.items().map(\.text) == ["Hello"])
    }

    @Test func roomsTakeTextAndLinksOnly() {
        let room = Contact(id: "room:r1", name: "Launch room", kind: .room(memberIDs: ["writer"]))
        let bot = Contact(id: "writer", name: "Writer")
        let text = SharedItem(id: UUID(), text: "Hi", files: [], problems: nil, created: .now)
        let photo = SharedItem(id: UUID(), text: "", files: ["cat.png"], problems: nil, created: .now)
        #expect(text.problem(sendingTo: room) == nil)
        #expect(photo.problem(sendingTo: room) == "Rooms take text and links only. Pick a Bot to send files.")
        #expect(photo.problem(sendingTo: bot) == nil)
    }
}

@MainActor
struct SharedInboxTests {
    private let hermes = Contact(id: "hermes", name: "Hermes", chatID: "stored-1")
    private let room = Contact(id: "room:r1", name: "Launch room", kind: .room(memberIDs: ["hermes"]))

    /// A signed-in model with a shared folder, which doesn't dial the gateway.
    private func model(_ folder: ShareFolder) async throws -> AppModel {
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
        model.setForeground(false)
        await model.restore()
        model.contacts = [hermes, room]
        return model
    }

    private func share(_ folder: ShareFolder, text: String = "", files: [SharedContent.File] = []) throws
        -> SharedItem
    {
        var content = SharedContent()
        content.addText(text)
        for file in files { content.add(file) }
        return try folder.container.add(content)
    }

    @Test func theShareLinkShowsWhatWasSharedOnceSignedIn() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let model = try await model(folder)
        let item = try share(folder, text: "https://example.com/post")
        #expect(model.sharedItem == nil)

        model.open(URL(string: "usualbot://share")!)
        #expect(model.sharedItem == item)

        // Closed without choosing: asked again when the app next comes to the front.
        model.putOffShared()
        #expect(model.sharedItem == nil)
        model.lookForSharedItems()
        #expect(model.sharedItem == item)

        model.signOut()
        #expect(model.sharedItem == nil)
    }

    @Test func choosingABotPutsTheTextAfterTheDraftAndTheFilesBesideItAndOpensTheChat() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let model = try await model(folder)
        model.drafts[hermes.id] = "Have a look"
        let pdf = try folder.file("report.pdf", Data("%PDF".utf8))
        let item = try share(folder, text: "https://example.com/post", files: [pdf])
        model.lookForSharedItems()

        #expect(model.putShared(item, in: hermes) == nil)

        #expect(model.drafts[hermes.id] == "Have a look\n\nhttps://example.com/post")
        let attached = model.thread(for: hermes).returnedAttachments
        #expect(attached.map(\.name) == ["report.pdf"])
        #expect(attached.map(\.data) == [Data("%PDF".utf8)])
        #expect(model.requestedContactID == hermes.id)
        #expect(model.sharedItem == nil)
        #expect(folder.container.items().isEmpty)
    }

    @Test func aRoomTakesTheTextButNotFiles() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let model = try await model(folder)
        let photo = try share(folder, files: [try folder.file("cat.png", Data([1]))])
        let link = try share(folder, text: "https://example.com")
        model.lookForSharedItems()

        #expect(model.putShared(photo, in: room) == "Rooms take text and links only. Pick a Bot to send files.")
        #expect(model.sharedItem == photo)
        model.discardShared(photo)
        #expect(model.sharedItem == link)

        #expect(model.putShared(link, in: room) == nil)
        #expect(model.drafts[room.id] == "https://example.com")
        #expect(model.sharedItem == nil)
    }

    @Test func aFileGoneFromTheFolderSaysSoAndLeavesTheItem() async throws {
        let folder = ShareFolder()
        defer { folder.remove() }
        let model = try await model(folder)
        let item = try share(folder, files: [try folder.file("notes.txt", Data("x".utf8))])
        model.lookForSharedItems()
        try FileManager.default.removeItem(at: folder.container.fileURL("notes.txt", of: item))

        #expect(model.putShared(item, in: hermes) == "notes.txt is no longer on this device.")
        #expect(model.sharedItem == item)
        #expect(model.thread(for: hermes).returnedAttachments.isEmpty)
    }
}
