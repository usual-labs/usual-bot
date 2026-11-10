import Foundation
import Observation
import os

/// Whether TestFlight has a newer build of the app than this one.
///
/// An app can't ask TestFlight, so TestFlight builds ask Usual's update check at bot.usual.dev
/// (`Services/updates`), which asks App Store Connect. The request carries nothing about you. Other
/// builds have no address for it (`UsualUpdatesURL` in Info.plist) and never ask.
@MainActor
@Observable
public final class AppUpdate {
    public struct Build: Equatable, Sendable {
        public let version: String
        public let build: String
        /// A newer build of the version you have, as nightly builds are: saying "0.5.0 is out" to
        /// someone on 0.5.0 would read as nothing new.
        public let isSameVersion: Bool
        /// The app's page in the TestFlight app, where Update installs it.
        public let testFlight: URL
    }

    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// A newer build, even one you put off: Settings shows it.
    public private(set) var newest: Build?
    /// A newer build you haven't put off: the sidebar offers it.
    public var available: Build? {
        guard let newest, newest.build != putOffBuild else { return nil }
        return newest
    }

    private let feed: URL?
    private let installedVersion: String
    private let installedBuild: String
    private let defaults: UserDefaults
    private let fetch: Fetch
    private var putOffBuild: String?
    private static let putOffKey = "updatePutOffBuild"
    private static let log = Logger(subsystem: "UsualBot", category: "update")

    public init(
        feed: URL?, installedVersion: String, installedBuild: String, defaults: UserDefaults = .standard,
        fetch: @escaping Fetch
    ) {
        self.feed = feed
        self.installedVersion = installedVersion
        self.installedBuild = installedBuild
        self.defaults = defaults
        self.fetch = fetch
        putOffBuild = defaults.string(forKey: Self.putOffKey)
    }

    public static func fromMainBundle() -> AppUpdate {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["UsualUpdatesURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return AppUpdate(
            feed: feed, installedVersion: info["CFBundleShortVersionString"] as? String ?? "",
            installedBuild: info["CFBundleVersion"] as? String ?? "0"
        ) { url in
            let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    /// Checks now and every few hours while the app runs. The service caches Apple's answer for an
    /// hour, so asking more often would show nothing sooner.
    public func watch() async {
        guard feed != nil else { return }
        while !Task.isCancelled {
            await check()
            try? await Task.sleep(for: .seconds(6 * 3600))  // sleep-ok: the next check, hours away
        }
    }

    /// Asks once. A failure keeps what it knew; the next check tries again.
    public func check() async {
        guard let feed else { return }
        do {
            let answer = try JSONDecoder().decode(Answer.self, from: try await fetch(feed))
            #if os(macOS)
                let entry = answer.macos
            #else
                let entry = answer.ios
            #endif
            // The Apple ID goes into a URL, so it must be the number it should be.
            guard let entry, !answer.app.isEmpty, answer.app.allSatisfy(\.isASCIIDigit),
                let page = URL(string: "itms-beta://beta.itunes.apple.com/v1/app/\(answer.app)")
            else { return }
            newest =
                Self.isNewer(entry.build, than: installedBuild)
                ? Build(
                    version: entry.version ?? "", build: entry.build,
                    isSameVersion: entry.version == installedVersion, testFlight: page) : nil
        } catch {
            Self.log.info("update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Later: the sidebar stops offering this build, and offers the next one.
    public func putOff() {
        guard let newest else { return }
        putOffBuild = newest.build
        defaults.set(newest.build, forKey: Self.putOffKey)
    }

    /// Build numbers are the upload time (`scripts/testflight.sh`), so they compare as numbers.
    nonisolated static func isNewer(_ build: String, than installed: String) -> Bool {
        build.compare(installed, options: .numeric) == .orderedDescending
    }

    private struct Answer: Decodable {
        struct Entry: Decodable {
            let version: String?
            let build: String
        }
        let app: String
        let macos: Entry?
        let ios: Entry?
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
