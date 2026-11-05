import Foundation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
@Suite("Push settings")
struct PushSettingsTests {
    private static let registration = PushRelay.Registration(
        id: "dev1", secret: "s", sendKey: "send-key", sealKey: Data(repeating: 7, count: 32), token: "ab",
        environment: "sandbox")

    /// Push settings hold their model weakly, so tests that only keep `push` keep the model here.
    private static var models: [AppModel] = []

    private final class Requests: Sendable {
        let log = Mutex<[(String, String)]>([])
        var lines: [String] { log.withLock { $0.map(\.0) } }
        func body(_ line: String) -> String? { log.withLock { $0.last { $0.0 == line }?.1 } }
    }

    /// A signed-in model whose gateway answers `settings`, and records every request.
    private func makeModel(settings: String = #"{"devices":[]}"#, status: Int = 200) async throws -> (
        PushSettings, AppModel, Requests
    ) {
        let requests = Requests()
        let store = MemoryTokenStore()
        let tokens = TokenSet(
            accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
            userID: "u1")
        try store.save(tokens, for: testGateway)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let model = AppModel(
            tokenStore: store,
            http: ScriptedHTTP { request in
                let line = "\(request.httpMethod ?? "") \(request.url?.path() ?? "")"
                let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
                requests.log.withLock { $0.append((line, body)) }
                if request.url?.lastPathComponent == "settings" { return (status, settings) }
                if line.hasPrefix("PUT /api/plugins/usual-push/devices") { return (200, #"{"id":"dev1","muted":[]}"#) }
                return (200, "{}")
            }, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        model.relay = PushRelay(relay: URL(string: "https://relay.example.com")!, registration: Self.registration)
        model.setForeground(false)
        await model.restore()
        Self.models.append(model)
        return (model.push, model, requests)
    }

    @Test func aGatewayWithoutThePluginSaysSo() async throws {
        let (push, _, _) = try await makeModel(settings: "{}", status: 404)
        await push.refresh()
        #expect(push.phase == .notInstalled)
        #expect(!push.isActive)
    }

    @Test func aNewDeviceGivesTheGatewayItsKeysAndChoices() async throws {
        let (push, _, requests) = try await makeModel()
        push.currentChoices = { .init(previews: false) }
        await push.refresh()
        #expect(push.isActive)
        let body = try #require(requests.body("PUT /api/plugins/usual-push/devices/dev1"))
        #expect(body.contains(#""send_key":"send-key""#))
        #expect(body.contains(#""seal_key":"\#(Self.registration.sealKey.base64EncodedString())""#))
        #expect(body.contains(#""relay":"https:\/\/relay.example.com""#))
        #expect(body.contains(#""previews":false"#))
    }

    @Test func aKnownDeviceIsntAddedAgainAndKeepsWhatItMuted() async throws {
        let (push, _, requests) = try await makeModel(
            settings: #"{"devices":[{"id":"dev1","relay":"https://relay.example.com","muted":["forge"]}]}"#)
        await push.refresh()
        #expect(push.isActive)
        #expect(push.muted == ["forge"])
        #expect(!requests.lines.contains { $0.hasPrefix("PUT") })
    }

    @Test func mutingABotSendsTheWholeList() async throws {
        let (push, _, requests) = try await makeModel(
            settings: #"{"devices":[{"id":"dev1","relay":"https://relay.example.com","muted":["forge"]}]}"#)
        await push.refresh()
        try await push.setMuted("atlas", true)
        let body = try #require(requests.body("PUT /api/plugins/usual-push/devices/dev1"))
        #expect(body.contains(#""muted":["atlas","forge"]"#))
    }

    @Test func aTestNamesThisDevice() async throws {
        let (push, _, requests) = try await makeModel(
            settings: #"{"devices":[{"id":"dev1","relay":"https://relay.example.com"}]}"#)
        await push.refresh()
        try await push.sendTest()
        #expect(requests.body("POST /api/plugins/usual-push/test") == #"{"device":"dev1"}"#)
    }

    @Test func aRelayAtANewAddressIsToldToTheGatewayAgain() async throws {
        let (push, _, requests) = try await makeModel(
            settings: #"{"devices":[{"id":"dev1","relay":"https://old.example.com","muted":["forge"]}]}"#)
        await push.refresh()
        #expect(push.isActive)
        let body = try #require(requests.body("PUT /api/plugins/usual-push/devices/dev1"))
        #expect(body.contains(#""relay":"https:\/\/relay.example.com""#))
    }

    @Test func signingOutTakesThisDeviceOffTheGateway() async throws {
        let (push, model, requests) = try await makeModel(
            settings: #"{"devices":[{"id":"dev1","relay":"https://relay.example.com","muted":["forge"]}]}"#)
        await push.refresh()
        model.signOut()
        #expect(!push.isActive)
        #expect(push.muted.isEmpty)
        try await waitUntil { requests.lines.contains("DELETE /api/plugins/usual-push/devices/dev1") }
    }

    private func presence(_ requests: Requests) -> [String] {
        requests.log.withLock { $0.filter { $0.0.hasSuffix("/presence") }.map(\.1) }
    }

    @Test func anOpenChatRepeatsSoTheGatewayKeepsItQuiet() async throws {
        let (push, _, requests) = try await makeModel(
            settings: #"{"devices":[{"id":"dev1","relay":"https://relay.example.com"}]}"#)
        await push.refresh()
        push.isWindowFocused = true
        await push.report(visible: "forge", names: [:])
        await push.report(visible: "forge", names: [:])
        let sent = presence(requests)
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.contains(#""chat":"forge""#) && $0.contains(#""device":"dev1""#) })
    }

    @Test func noChatIsSaidOnceSoAMacCantOverruleAPhoneInUse() async throws {
        let (push, _, requests) = try await makeModel(
            settings: #"{"devices":[{"id":"dev1","relay":"https://relay.example.com"}]}"#)
        await push.refresh()
        push.isWindowFocused = true
        await push.report(visible: "forge", names: [:])
        push.isWindowFocused = false
        await push.report(visible: "forge", names: [:])
        await push.report(visible: "forge", names: [:])
        let sent = presence(requests)
        #expect(sent.count == 2)
        #expect(sent.last?.contains(#""chat""#) == false)
    }

    @Test func theQuickPanelCountsAsFocus() async throws {
        let (_, model, _) = try await makeModel()
        #expect(!model.isFocused)
        model.setPanelOpen(true)
        #expect(model.isFocused)
        model.setWindowFocused(true)
        model.setPanelOpen(false)
        #expect(model.isFocused)
        model.setWindowFocused(false)
        #expect(!model.isFocused)
    }

    @Test func aNotificationLinkOpensItsChat() async throws {
        let (_, model, _) = try await makeModel()
        model.open(URL(string: "usualbot://chat/head-of-sales")!)
        #expect(model.requestedContactID == "head-of-sales")
        model.open(URL(string: "usualbot://chat/room%3Aabc-123")!)
        #expect(model.requestedContactID == "room:abc-123")
    }

    @Test func anyOtherLinkDoesNothing() async throws {
        let (_, model, _) = try await makeModel()
        model.open(URL(string: "usualbot://settings/x")!)
        model.open(URL(string: "https://chat/forge")!)
        model.open(URL(string: "usualbot://chat/a/b")!)
        #expect(model.requestedContactID == nil)
    }
}
