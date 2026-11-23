import Foundation
import Testing

@testable import HermesKit

@MainActor
struct DraftsTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "usualbot-drafts-\(UUID().uuidString)")
    }

    private func model(drafts directory: URL? = nil) -> AppModel {
        AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            draftsDirectory: directory, makeSocket: { _ in FakeSocket() })
    }

    @Test func eachChatKeepsItsOwnDraftAcrossLaunches() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = Drafts(directory: directory)
        drafts.load(for: testGateway)
        drafts["forge"] = "Ship it on"
        drafts["room:team"] = "@atlas what do you"
        #expect(drafts["forge"] == "Ship it on")
        #expect(drafts["scribe"].isEmpty)
        drafts.save()

        let relaunched = Drafts(directory: directory)
        relaunched.load(for: testGateway)
        #expect(relaunched["forge"] == "Ship it on")
        #expect(relaunched["room:team"] == "@atlas what do you")

        // Another gateway's chats have their own, in a file that doesn't spell the address out.
        let elsewhere = Drafts(directory: directory)
        elsewhere.load(for: try GatewayAddress(parsing: "10.0.0.1:9119"))
        #expect(elsewhere["forge"].isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1 && !files[0].contains("100.101"))
    }

    @Test func repliesWaitingAboveTheBoxAreKeptWithTheDraft() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = Drafts(directory: directory)
        drafts.load(for: testGateway)
        let quote = DraftQuote(
            author: "Forge", excerpt: "X ads setup", mention: nil, lines: ["X ads setup"], note: "hello")
        // A reply with nothing typed in the box is a draft on its own.
        drafts[quotes: "forge"] = [quote]
        #expect(drafts["forge"].isEmpty)
        drafts.save()

        let relaunched = Drafts(directory: directory)
        relaunched.load(for: testGateway)
        #expect(relaunched[quotes: "forge"] == [quote])
        #expect(relaunched[quotes: "scribe"].isEmpty)

        relaunched[quotes: "forge"] = []
        relaunched.save()
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty != false)
    }

    @Test func draftsWrittenBeforeRepliesWereKeptStillLoad() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(["forge": "Ship it"]).write(to: directory.appending(path: testGateway.fileName))

        let drafts = Drafts(directory: directory)
        drafts.load(for: testGateway)
        #expect(drafts["forge"] == "Ship it")
    }

    @Test func sendingOrClearingTheBoxRemovesTheDraft() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = Drafts(directory: directory)
        drafts.load(for: testGateway)
        drafts["forge"] = "Ship it"
        drafts["atlas"] = " \n"
        drafts.save()
        drafts["forge"] = ""
        drafts.save()

        let relaunched = Drafts(directory: directory)
        relaunched.load(for: testGateway)
        #expect(relaunched["forge"].isEmpty)
        // Spaces alone aren't kept, and with nothing to keep there is no file.
        #expect(relaunched["atlas"].isEmpty)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty != false)
    }

    @Test func theAppReadsItsDraftsWhenItRestoresTheSignIn() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let written = Drafts(directory: directory)
        written.load(for: testGateway)
        written["forge"] = "Ship it"
        written.save()

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
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            draftsDirectory: directory, makeSocket: { _ in FakeSocket() })
        // In the background, so nothing connects.
        model.setForeground(false)
        await model.restore()

        #expect(model.drafts["forge"] == "Ship it")
    }

    @Test func signingOutDeletesDrafts() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = model(drafts: directory)
        model.drafts.load(for: testGateway)
        model.drafts["forge"] = "Ship it"
        model.drafts.save()

        model.signOut()

        #expect(model.drafts["forge"].isEmpty)
        let relaunched = Drafts(directory: directory)
        relaunched.load(for: testGateway)
        #expect(relaunched["forge"].isEmpty)
    }

    @Test func aDraftFollowsARenamedBotAndGoesWithADeletedOne() throws {
        let model = model()
        model.drafts["scout"] = "Find the"
        model.drafts["ops"] = "Restart"
        let quote = DraftQuote(author: "Scout", excerpt: "Found it", mention: nil, lines: ["Found it"], note: "")
        model.drafts[quotes: "scout"] = [quote]
        model.drafts[quotes: "ops"] = [quote]

        model.moveAgent(from: "scout", to: "finder")
        model.forgetAgent("ops")

        #expect(model.drafts["finder"] == "Find the")
        #expect(model.drafts["scout"].isEmpty)
        #expect(model.drafts["ops"].isEmpty)
        #expect(model.drafts[quotes: "finder"] == [quote])
        #expect(model.drafts[quotes: "scout"].isEmpty)
        #expect(model.drafts[quotes: "ops"].isEmpty)
    }
}
