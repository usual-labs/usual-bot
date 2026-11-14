import Foundation
import Synchronization
import Testing

@testable import HermesKit

/// Two gateways on one device: one in use, the other signed in and waiting.
@MainActor
struct GatewaySwitchingTests {
    private let home = try! GatewayAddress(parsing: "https://hermes.example.com")
    private let tokens = TokenSet(
        accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
        userID: "u1")

    private final class Requests: Sendable {
        let log = Mutex<[(String, String)]>([])
        func bodies(_ line: String) -> [String] { log.withLock { $0.filter { $0.0 == line }.map(\.1) } }
    }

    /// Signed in to `testGateway`, and to `home` too when `both`, with `testGateway` in use.
    private func makeModel(both: Bool = true, defaults: UserDefaults? = nil) throws -> (
        AppModel, MemoryTokenStore, UserDefaults
    ) {
        let store = MemoryTokenStore()
        try store.save(tokens, for: testGateway)
        if both { try store.save(tokens, for: home) }
        let defaults = defaults ?? UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(testGateway.baseURL.absoluteString, forKey: "gatewayAddress")
        let model = AppModel(
            tokenStore: store, http: ScriptedHTTP { _ in (200, "{}") }, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)),
            makeSocket: { _ in FakeSocket() })
        model.gatewayList.keepsNames = false
        if both {
            model.gateways.append(SavedGateway(address: home))
            model.gatewayList.save(model.gateways)
        }
        model.setForeground(false)
        return (model, store, defaults)
    }

    private func waitUntilSignedIn(_ model: AppModel) async {
        for _ in 0..<200 where model.auth == nil {
            // sleep-ok: the sign-in is read off the main thread
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func anInstallFromBeforeKeepsItsGatewayAsTheFirst() throws {
        let (model, _, defaults) = try makeModel(both: false)
        #expect(model.gateways.map(\.address) == [testGateway])
        #expect(model.activeGateway?.address == testGateway)
        // The ID it was given is kept, as the push plugin is told it.
        let again = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") }, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)))
        #expect(again.gateways == model.gateways)
    }

    @Test func switchingShowsTheOtherGatewayAndComesBackToWhereYouWere() async throws {
        let (model, _, defaults) = try makeModel()
        await model.restore()
        #expect(model.session == .signedIn(testGateway))
        defaults.set("forge", forKey: AppModel.selectedContactKey)

        let other = try #require(model.gateways.first { $0.address == home })
        model.switchTo(other.id)
        #expect(model.session == .signedIn(home))
        #expect(defaults.string(forKey: "gatewayAddress") == home.baseURL.absoluteString)
        // Its own `default`, not the other gateway's `forge`.
        #expect(defaults.string(forKey: AppModel.selectedContactKey) == nil)
        await waitUntilSignedIn(model)
        #expect(model.auth?.gateway == home)
        defaults.set("default", forKey: AppModel.selectedContactKey)

        model.switchTo(model.gateways[0].id)
        #expect(model.session == .signedIn(testGateway))
        #expect(defaults.string(forKey: AppModel.selectedContactKey) == "forge")
        model.switchTo(other.id)
        #expect(defaults.string(forKey: AppModel.selectedContactKey) == "default")
    }

    @Test func signingOutGoesOnToTheOtherGateway() async throws {
        let (model, store, _) = try makeModel()
        await model.restore()
        model.signOut()
        #expect(model.gateways.map(\.address) == [home])
        #expect(model.session == .signedIn(home))
        #expect(try store.load(for: home) != nil)
        await waitUntilSignedIn(model)
        #expect(model.auth?.gateway == home)

        model.signOut()
        #expect(model.gateways.isEmpty)
        #expect(model.session == .signedOut)
    }

    @Test func addingAGatewayYouHaveSaysSoAndCancelGoesBack() async throws {
        let (model, _, _) = try makeModel(both: false)
        await model.restore()
        #expect(model.canAddGateway)
        model.addGateway()
        #expect(model.session == .signedOut)
        #expect(model.returnGatewayID == model.gateways[0].id)

        model.gatewayInput = "100.101.102.103:9119"
        model.signIn(presenter: NeverSignIn())
        for _ in 0..<200 where model.problem == nil {
            // sleep-ok: the check runs in the sign-in task
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.problem == "You’re already connected to this gateway.")
        #expect(model.gateways.count == 1)

        model.cancelAddingGateway()
        #expect(model.returnGatewayID == nil)
        #expect(model.session == .signedIn(testGateway))
    }

    @Test func twoGatewaysIsTheMost() async throws {
        let (model, _, _) = try makeModel()
        await model.restore()
        #expect(!model.canAddGateway)
        model.addGateway()
        #expect(model.session == .signedIn(testGateway))
    }

    @Test func aRenamedGatewayGoesByItsName() throws {
        let (model, _, defaults) = try makeModel()
        model.rename(model.gateways[1].id, to: "  Home ")
        #expect(model.gateways[1].displayName == "Home")
        let again = AppModel(
            tokenStore: MemoryTokenStore(), http: ScriptedHTTP { _ in (200, "{}") }, defaults: defaults,
            cache: OfflineCache(directory: .temporaryDirectory.appending(path: UUID().uuidString)))
        #expect(again.gateways[1].name == "Home")
        model.rename(model.gateways[1].id, to: "")
        #expect(model.gateways[1].displayName == "hermes.example.com")
    }

    @Test func newsIsOnlyForTheGatewayYoureNotUsing() async throws {
        let (model, _, _) = try makeModel()
        await model.restore()
        model.showNews(on: Set(model.gateways.map(\.id)))
        #expect(model.gatewaysWithNews == [model.gateways[1].id])
    }
}

/// A browser sign-in the tests here never reach.
private final class NeverSignIn: SignInPresenter {
    func present(_ url: URL, onCancel: @escaping @MainActor () -> Void) {}
    func dismiss() {}
}
