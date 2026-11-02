import Foundation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
@Suite("Push settings")
struct PushSettingsTests {
    private func makeModel(_ answer: @escaping @Sendable (URLRequest) -> (Int, String)) throws -> (
        PushSettings, AppModel
    ) {
        let store = MemoryTokenStore()
        let tokens = TokenSet(
            accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
            userID: "u1")
        try store.save(tokens, for: testGateway)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let model = AppModel(
            tokenStore: store, http: ScriptedHTTP(answer), defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        return (model.push, model)
    }

    @Test func aGatewayWithoutThePluginSaysSo() async throws {
        let (push, model) = try makeModel { _ in (404, "{}") }
        model.setForeground(false)
        await model.restore()
        await push.refresh()
        #expect(push.phase == .notInstalled)
        #expect(!push.isActive)
    }

    @Test func secretsAreKnownOnlyAsSaved() async throws {
        let (push, model) = try makeModel { _ in
            (200, #"{"service":"pushover","has_token":true,"has_user_key":true,"topic":""}"#)
        }
        model.setForeground(false)
        await model.restore()
        await push.refresh()
        #expect(push.service == .pushover)
        #expect(push.hasToken && push.hasUserKey)
        #expect(push.isActive)
    }

    @Test func aTestGoesThroughWhatsInSettingsNotWhatWasSaved() async throws {
        let log = Mutex<[String]>([])
        let (push, model) = try makeModel { request in
            let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
            log.withLock { $0.append("\(request.httpMethod ?? "") \(request.url?.lastPathComponent ?? "")") }
            if request.httpMethod == "PUT" {
                #expect(body.contains(#""service":"ntfy""#))
                #expect(body.contains(#""ntfy_token":"tk_new""#))
                #expect(!body.contains(#""token":"#))
            }
            return (200, #"{"service":"pushover","topic":"","has_token":true,"has_user_key":true}"#)
        }
        model.setForeground(false)
        await model.restore()
        await push.refresh()
        log.withLock { $0.removeAll() }
        push.service = .ntfy
        push.topic = "my-agents"
        try await push.saveAndSendTest(
            .init(ntfyToken: "tk_new", messages: true, needsYou: true, previews: true))
        #expect(log.withLock { $0 } == ["PUT settings", "POST test"])
    }

    @Test func ntfyNeedsATopic() async throws {
        let (push, model) = try makeModel { _ in (200, #"{"service":"ntfy","topic":""}"#) }
        model.setForeground(false)
        await model.restore()
        await push.refresh()
        #expect(!push.isActive)
        push.topic = "my-agents"
        #expect(push.isActive)
    }

    @Test func signingOutForgetsTheService() async throws {
        let (push, model) = try makeModel { _ in (200, #"{"service":"ntfy","topic":"t"}"#) }
        model.setForeground(false)
        await model.restore()
        await push.refresh()
        model.signOut()
        #expect(!push.isActive)
        #expect(push.topic.isEmpty)
    }

    private final class Reports: Sendable {
        let bodies = Mutex<[String]>([])
    }

    private func presenceReports() async throws -> (AppModel, Reports) {
        let reports = Reports()
        let (push, model) = try makeModel { request in
            if request.url?.lastPathComponent == "presence" {
                let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
                reports.bodies.withLock { $0.append(body) }
            }
            return (200, #"{"service":"ntfy","topic":"my-agents"}"#)
        }
        model.setForeground(false)
        await model.restore()
        await push.refresh()
        return (model, reports)
    }

    @Test func focusRepeatsSoThePluginKeepsHoldingPushes() async throws {
        let (model, reports) = try await presenceReports()
        let push = model.push
        push.isWindowFocused = true
        await push.report(names: [:])
        await push.report(names: [:])
        let sent = reports.bodies.withLock { $0 }
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.contains(#""focused":true"#) })
    }

    @Test func leavingIsSaidOnceSoAMacCantOverruleAPhoneInUse() async throws {
        let (model, reports) = try await presenceReports()
        let push = model.push
        push.isWindowFocused = true
        await push.report(names: [:])
        push.isWindowFocused = false
        await push.report(names: [:])
        await push.report(names: [:])
        let sent = reports.bodies.withLock { $0 }
        #expect(sent.count == 2)
        #expect(sent.last?.contains(#""focused":false"#) == true)
    }

    @Test func theQuickPanelCountsAsFocus() async throws {
        let (model, _) = try await presenceReports()
        #expect(!model.isFocused)
        model.setPanelOpen(true)
        #expect(model.isFocused)
        model.setWindowFocused(true)
        model.setPanelOpen(false)
        #expect(model.isFocused)
        model.setWindowFocused(false)
        #expect(!model.isFocused)
    }

    @Test func aNotificationLinkOpensItsChat() throws {
        let (_, model) = try makeModel { _ in (200, "{}") }
        model.open(URL(string: "usualbot://chat/head-of-sales")!)
        #expect(model.requestedContactID == "head-of-sales")
        model.open(URL(string: "usualbot://chat/room%3Aabc-123")!)
        #expect(model.requestedContactID == "room:abc-123")
    }

    @Test func anyOtherLinkDoesNothing() throws {
        let (_, model) = try makeModel { _ in (200, "{}") }
        model.open(URL(string: "usualbot://settings/x")!)
        model.open(URL(string: "https://chat/forge")!)
        model.open(URL(string: "usualbot://chat/a/b")!)
        #expect(model.requestedContactID == nil)
    }
}
