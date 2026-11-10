import Foundation
import Testing

@testable import HermesKit

/// Telling a TestFlight build that a newer one is out, from bot.usual.dev's answer.
@MainActor
struct AppUpdateTests {
    private let feed = URL(string: "https://bot.usual.dev/v1/latest")!

    private func update(
        version: String = "0.5.0", installed: String = "202611010900", answer: String,
        defaults: UserDefaults = .init(suiteName: UUID().uuidString)!
    ) -> AppUpdate {
        AppUpdate(feed: feed, installedVersion: version, installedBuild: installed, defaults: defaults) { _ in
            Data(answer.utf8)
        }
    }

    private func answer(build: String, app: String = "6754321098") -> String {
        let entry = #"{"version":"0.6.0","build":"\#(build)"}"#
        return #"{"app":"\#(app)","macos":\#(entry),"ios":\#(entry)}"#
    }

    @Test func aNewerBuildIsOfferedWithItsTestFlightPage() async throws {
        let update = update(answer: answer(build: "202611090217"))
        await update.check()
        let available = try #require(update.available)
        #expect(available.version == "0.6.0")
        #expect(!available.isSameVersion)
        #expect(available.build == "202611090217")
        #expect(available.testFlight.absoluteString == "itms-beta://beta.itunes.apple.com/v1/app/6754321098")
    }

    @Test func aNewerBuildOfTheSameVersionSaysSo() async {
        let update = update(version: "0.6.0", answer: answer(build: "202611090217"))
        await update.check()
        #expect(update.available?.isSameVersion == true)
    }

    @Test func theSameOrAnOlderBuildIsNotOffered() async {
        for build in ["202611010900", "202610300100"] {
            let update = update(answer: answer(build: build))
            await update.check()
            #expect(update.available == nil)
        }
    }

    @Test func buildNumbersCompareAsNumbers() async {
        let update = update(installed: "9", answer: answer(build: "10"))
        await update.check()
        #expect(update.available?.build == "10")
    }

    @Test func laterHidesThatBuildButNotTheNextOne() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = update(answer: answer(build: "202611090217"), defaults: defaults)
        await first.check()
        first.putOff()
        #expect(first.available == nil)
        // Settings still shows it.
        #expect(first.newest?.build == "202611090217")

        let relaunched = update(answer: answer(build: "202611090217"), defaults: defaults)
        await relaunched.check()
        #expect(relaunched.available == nil)

        let next = update(answer: answer(build: "202611100217"), defaults: defaults)
        await next.check()
        #expect(next.available?.build == "202611100217")
    }

    @Test func anAnswerItCantUseChangesNothing() async {
        for bad in ["not json", #"{"app":"1","macos":null,"ios":null}"#, answer(build: "202611090217", app: "x/../y")] {
            let update = update(answer: bad)
            await update.check()
            #expect(update.newest == nil)
        }
    }

    @Test func aBuildWithoutAFeedNeverAsks() async {
        let update = AppUpdate(
            feed: nil, installedVersion: "0.5.0", installedBuild: "1", defaults: .init(suiteName: UUID().uuidString)!
        ) { _ in
            Issue.record("asked without a feed")
            return Data()
        }
        await update.check()
        #expect(update.newest == nil)
    }
}
