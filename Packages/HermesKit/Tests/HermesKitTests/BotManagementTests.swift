import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HermesKit

struct BotNameTests {
    @Test func aTypedNameBecomesAProfileNameHermesTakes() {
        #expect(BotName("  Throwaway Test ").profile == "throwaway-test")
        #expect(BotName("  Throwaway Test ").title == "Throwaway Test")
        #expect(BotName("Résumé Bot!").profile == "resume-bot")
        #expect(BotName("job_scout 2").profile == "job_scout-2")
        #expect(BotName("小助手").profile == "u5c0f-u52a9-u624b")
        #expect(BotName("-Ops-").profile == "ops")
    }

    @Test func aLongNameIsCutWithoutSplittingAToken() {
        let profile = BotName(String(repeating: "word ", count: 20)).profile
        #expect(profile.count <= 64)
        #expect(profile.hasSuffix("word"))
        #expect(profile.wholeMatch(of: /[a-z0-9][a-z0-9_-]{0,63}/) != nil)
    }

    @Test func namesHermesRefusesSayWhy() {
        #expect(BotName("   ").problem(taken: []) == "Give your Bot a name.")
        #expect(BotName("!!!").problem(taken: []) == "Use at least one letter or number in the name.")
        #expect(BotName("Hermes").problem(taken: [])?.contains("keeps the name") == true)
        #expect(BotName("Default").problem(taken: [])?.contains("keeps the name") == true)
        #expect(BotName("Scout").problem(taken: ["scout"])?.contains("already a Bot") == true)
        #expect(BotName("Scout").problem(taken: ["ops"]) == nil)
    }
}

struct BotProfilesTests {
    private func channel(_ gateway: ScriptedGateway) async -> JSONRPCChannel {
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        return channel
    }

    private let saved: JSONValue = ["ok": true, "applied": ["ui_meta": true]]

    @Test func creatingAsksForAFreshProfileWithItsNameInItsSoul() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let created = BotProfiles.create(BotName("Throwaway Test"), description: "Tries things", on: channel)

        let params = try await gateway.answer(
            0, method: "profiles.create", result: ["ok": true, "name": "throwaway-test", "path": "/x"])
        #expect(try await created == "throwaway-test")
        #expect(params["name"] == "throwaway-test")
        #expect(params["description"] == "Tries things")
        #expect(params["share_auth"] == true)
        // Fresh, not a copy: no clone_from, so no other Bot's SOUL, keys or MCP servers come along.
        #expect(params["clone_from"] == nil)
        let soul = params["soul"]?.stringValue ?? ""
        #expect(soul.hasPrefix("# Throwaway Test"))
        #expect(soul.contains("(profile `throwaway-test`)"))
        #expect(soul.contains("**Mission:** Tries things"))
    }

    @Test func aRenameSavesOnlyTheTitle() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let write: Void = BotMetaWrite.setTitle("Scouty", profile: "scout", on: channel)

        let row: JSONValue = [
            "name": "scout", "ui_meta": ["hermes-bots": ["title": "Scout", "sectionId": "s1", "shape": "blob"]],
            "ui_meta_revisions": ["hermes-bots": 4],
        ]
        _ = try await gateway.answer(0, method: "profiles.list", result: ["profiles": .array([row])])
        let sent = try await gateway.answer(1, method: "profiles.configure", result: saved)
        try await write
        #expect(sent["ui_meta"]?["hermes-bots"] == ["title": "Scouty", "sectionId": "s1", "shape": "blob"])
        #expect(sent["ui_meta_expected_revisions"] == ["hermes-bots": 4])
    }

    @Test func aPictureIsStoredThenMarkedAPhoto() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        let png = Data([1, 2, 3])
        async let write: Void = BotProfiles.setPicture(png, profile: "scout", on: channel)

        let asset = try await gateway.answer(0, method: "profiles.set_asset", result: ["ok": true, "asset": "avatar"])
        #expect(asset == ["name": "scout", "asset": "avatar", "data": "data:image/png;base64,AQID"])
        _ = try await gateway.answer(1, method: "profiles.list", result: ["profiles": [["name": "scout"]]])
        let sent = try await gateway.answer(2, method: "profiles.configure", result: saved)
        try await write
        #expect(sent["ui_meta"]?["hermes-bots"]?["imageKind"] == "photo")
    }

    @Test func removingAPictureClearsItAndGoesBackToTheFace() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        async let write: Void = BotProfiles.removePicture(profile: "scout", on: channel)

        let asset = try await gateway.answer(0, method: "profiles.set_asset", result: ["ok": true, "removed": 1])
        #expect(asset == ["name": "scout", "asset": "avatar", "clear": true])
        _ = try await gateway.answer(1, method: "profiles.list", result: ["profiles": [["name": "scout"]]])
        let sent = try await gateway.answer(2, method: "profiles.configure", result: saved)
        try await write
        #expect(sent["ui_meta"]?["hermes-bots"]?["imageKind"] == "shape")
    }

    @Test func deletingIsTheDashboardRoute() async throws {
        let http = ScriptedHTTP { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/api/profiles/job-scout")
            #expect(request.timeoutInterval >= 60)
            return (200, #"{"ok":true,"path":"/x"}"#)
        }
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        try await BotProfiles.delete(profile: "job-scout", auth: auth)
        #expect(http.requests.count == 1)
    }

    @MainActor @Test func aPictureIsCroppedToTheMiddleSquareAt256() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let png = try #require(BotPictureFile.prepare(data as Data))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(properties?[kCGImagePropertyPixelWidth] as? Int == 256)
        #expect(properties?[kCGImagePropertyPixelHeight] as? Int == 256)
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        #expect(!BotPictures.isDrawnFace(png))
        #expect(BotPictureFile.prepare(Data("not a picture".utf8)) == nil)
    }
}

struct RosterHoldsTests {
    private let scout = Contact(id: "scout", name: "Scout")
    private let ops = Contact(id: "ops", name: "Ops")

    @Test func aNewBotShowsUntilTheRosterListsIt() {
        var holds = RosterHolds()
        holds.add(Contact(id: "new", name: "New"))
        #expect(holds.apply(to: [scout]).map(\.id) == ["scout", "new"])
        #expect(holds.apply(to: [scout, Contact(id: "new", name: "new")]).map(\.id) == ["scout", "new"])
        #expect(holds.isEmpty)
    }

    @Test func aDeletedBotStaysGoneThroughAStaleRead() {
        var holds = RosterHolds()
        holds.remove("scout")
        #expect(holds.apply(to: [scout, ops]).map(\.id) == ["ops"])
        #expect(holds.apply(to: [ops]).map(\.id) == ["ops"])
        #expect(holds.isEmpty)
    }

    @Test func aRenameHoldsUntilTheRosterAgrees() {
        var holds = RosterHolds()
        holds.rename("scout", to: "Scouty")
        #expect(holds.apply(to: [scout]).first?.name == "Scouty")
        #expect(holds.apply(to: [Contact(id: "scout", name: "Scouty")]).first?.name == "Scouty")
        #expect(holds.isEmpty)
    }

    @Test func theGatewaysWordStandsAfterThreeReads() {
        var holds = RosterHolds()
        holds.rename("scout", to: "Scouty")
        holds.setPicture("scout", Contact.Picture(revision: -1, isPhoto: true))
        for _ in 0..<RosterHolds.reads {
            let shown = holds.apply(to: [scout])
            #expect(shown.first?.name == "Scouty")
            #expect(shown.first?.picture != nil)
        }
        let settled = holds.apply(to: [scout])
        #expect(settled.first?.name == "Scout")
        #expect(settled.first?.picture == nil)
        #expect(holds.isEmpty)
    }
}

@MainActor
struct BotStateTests {
    private func model() -> AppModel {
        AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") },
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
    }

    private func rows(_ json: String) throws -> [ProfileRow] {
        try JSONDecoder.gateway.decode(ProfileList.self, from: Data(json.utf8)).profiles
    }

    private func agent(_ id: String) -> Contact {
        Contact(id: id, name: id.capitalized, details: AgentDetails(profile: id))
    }

    @Test func aRenameOnTheGatewayCarriesTheChatAndPictureToTheNewID() throws {
        let model = model()
        model.contacts = [agent("scout"), agent("ops")]
        model.threads["scout"] = ChatThread.sample(
            "scout", state: ThreadState(history: [HistoryMessage(role: "user", text: "Hi")], running: false))
        model.pictures.show(Data([1]), for: "scout")
        _ = model.routines(for: model.contacts[0])
        model.visibleContactID = "scout"
        var cleared: [Contact.ID?] = []
        model.alertsCleared = { cleared.append($0) }

        model.followProfileChanges(
            try rows(#"{"profiles":[{"name":"finder","previous_names":["scout"]},{"name":"ops"}]}"#))

        #expect(model.threads["scout"] == nil)
        #expect(model.threads["finder"]?.state.items.isEmpty == false)
        #expect(model.threads["finder"]?.contactID == "finder")
        #expect(model.pictures.data(for: "finder") == Data([1]))
        #expect(model.pictures.data(for: "scout") == nil)
        #expect(model.routineLists["scout"] == nil)
        #expect(model.currentID(for: "scout") == "finder")
        #expect(model.currentID(for: "ops") == "ops")
        #expect(model.requestedContactID == "finder")
        #expect(cleared.contains("scout"))
        #expect(model.contacts.first?.id == "finder")
    }

    @Test func aBotDeletedElsewhereIsForgotten() throws {
        let model = model()
        model.contacts = [agent("scout"), agent("ops")]
        model.threads["scout"] = ChatThread.sample("scout", state: ThreadState(history: [], running: false))
        model.pictures.show(Data([1]), for: "scout")
        _ = model.connectors(for: model.contacts[0])
        _ = model.screen(for: model.contacts[0])
        model.visibleContactID = "scout"

        model.followProfileChanges(try rows(#"{"profiles":[{"name":"ops"}]}"#))

        #expect(model.threads["scout"] == nil)
        #expect(model.pictures.data(for: "scout") == nil)
        #expect(model.connectorLists["scout"] == nil)
        #expect(model.screens["scout"] == nil)
        #expect(model.visibleContactID == nil)
        #expect(model.currentID(for: "scout") == "scout")
    }

    @Test func aHiddenBotKeepsItsChat() throws {
        let model = model()
        model.contacts = [agent("ops")]
        model.threads["scout"] = ChatThread.sample("scout", state: ThreadState(history: [], running: false))
        model.followProfileChanges(
            try rows(#"{"profiles":[{"name":"ops"},{"name":"scout","ui_meta":{"hermes-bots":{"hidden":true}}}]}"#))
        #expect(model.threads["scout"] != nil)
    }

    @Test func aBotJustMadeHereIsntForgottenByAStaleRead() async throws {
        let model = model()
        model.isDemo = true
        model.contacts = [agent("ops")]
        let made = try await model.createBot(BotName("Scout"), description: nil, picture: nil)
        model.followProfileChanges(try rows(#"{"profiles":[{"name":"ops"}]}"#))
        #expect(model.threads[made.id] != nil)
        #expect(model.rosterHolds.apply(to: [agent("ops")]).map(\.id) == ["ops", "scout"])
    }

    @Test func deletingForgetsEverythingKeptAboutTheBot() async throws {
        let http = ScriptedHTTP { _ in (200, #"{"ok":true}"#) }
        let model = AppModel(
            tokenStore: MemoryTokenStore(), http: http, defaults: UserDefaults(suiteName: UUID().uuidString)!,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        model.auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        let scout = agent("scout")
        model.contacts = [scout, agent("ops")]
        model.threads["scout"] = ChatThread.sample("scout", state: ThreadState(history: [], running: false))
        model.pictures.show(Data([1]), for: "scout")
        _ = model.vault(for: scout)

        try await model.deleteBot(scout)

        #expect(http.requests.first?.url?.path == "/api/profiles/scout")
        #expect(model.contacts.map(\.id) == ["ops"])
        #expect(model.threads["scout"] == nil)
        #expect(model.vaultLists["scout"] == nil)
        #expect(model.pictures.data(for: "scout") == nil)
        // A roster read that started before the delete can't bring it back.
        #expect(model.rosterHolds.apply(to: [scout, agent("ops")]).map(\.id) == ["ops"])
    }

    @Test func theMainProfileCantBeDeleted() async throws {
        let model = model()
        let main = agent("default")
        model.contacts = [main]
        #expect(!model.canDeleteBot(main))
        try await model.deleteBot(main)
        #expect(model.contacts.count == 1)
    }

    @Test func offlineSaysWhyNothingCanChange() {
        let model = model()
        #expect(model.botEditingUnavailable != nil)
    }

    @Test func roomsWithTheBotAreFound() {
        let model = model()
        let room = Contact(id: "room:1", name: "Launch", kind: .room(memberIDs: ["scout", "ops"]))
        model.contacts = [
            agent("scout"), agent("ops"), room, Contact(id: "room:2", name: "Other", kind: .room(memberIDs: ["ops"])),
        ]
        #expect(model.rooms(including: agent("scout")).map(\.id) == ["room:1"])
    }
}

@MainActor
struct DemoBotTests {
    @Test func theDemoMakesRenamesAndDeletesBotsLocally() async throws {
        let model = AppModel.demo()
        let made = try await model.createBot(BotName("Throwaway Test"), description: "Tries things", picture: nil)
        #expect(made == NewBot(id: "throwaway-test", canReply: true, pictureFailed: false))
        let contact = try #require(model.contacts.first { $0.id == made.id })
        #expect(contact.name == "Throwaway Test")
        #expect(model.threads[made.id]?.phase == .ready)

        try await model.renameBot(contact, to: "Tester")
        #expect(model.contacts.first { $0.id == made.id }?.name == "Tester")

        // A file that isn't a picture still makes the Bot, and says the picture didn't save.
        let second = try await model.createBot(BotName("Tester two"), description: nil, picture: Data("x".utf8))
        #expect(second.pictureFailed)

        try await model.deleteBot(contact)
        #expect(model.contacts.contains { $0.id == made.id } == false)
        #expect(model.threads[made.id] == nil)
    }
}
