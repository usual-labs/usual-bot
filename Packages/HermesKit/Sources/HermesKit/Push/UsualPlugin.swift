import Foundation

/// The `usual-bot` plugin (`Integrations/usual-bot`): push, a Bot's browser, and telling a Bot in
/// the app's chats that it's talking through Usual Bot. Before 0.6.0 it was two plugins,
/// `usual-push` and `usual-browser`, and a gateway that hasn't updated still answers under their
/// names.
public enum UsualPlugin {
    public static let name = "usual-bot"
    /// The version this build was made with. An older one is offered as an update.
    public static let version = "0.9.0"

    static let path = "/api/plugins/usual-bot"
    static let oldPushPath = "/api/plugins/usual-push"
    static let oldBrowserPath = "/api/plugins/usual-browser"
    static let replaced = ["usual-push", "usual-browser"]

    /// What `plugins.manage` installs: this repository's folder, from its default branch. Hermes
    /// pins `ref` only to a full commit, and a build doesn't know its own.
    static let source = "usual-labs/usual-bot#Integrations/usual-bot"

    /// Whether `installed` is older than this build's plugin. A plugin that doesn't say is.
    public static func isOlder(_ installed: String?) -> Bool {
        guard let installed else { return true }
        func parts(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0) ?? 0 } }
        let mine = parts(version)
        let theirs = parts(installed)
        for index in 0..<max(mine.count, theirs.count) {
            let (a, b) = (index < theirs.count ? theirs[index] : 0, index < mine.count ? mine[index] : 0)
            if a != b { return a < b }
        }
        return false
    }

    /// Installs the plugin into each profile, or replaces the copy there, and then takes out the two
    /// it replaces. `force` is the user's yes to Hermes's install scan, which calls this plugin
    /// "caution" for reading Chrome's version and naming sudo prompts. Stops at the first profile
    /// that fails; the ones before it keep theirs. True when the gateway has to restart before the
    /// plugin runs: Hermes loads it into a running gateway itself, and says so when none answered.
    @discardableResult
    static func install(profiles: [String], on channel: JSONRPCChannel) async throws -> Bool {
        var restart = false
        for profile in profiles {
            let result = try await channel.call(
                "plugins.manage",
                params: [
                    "action": "install", "identifier": .string(source), "force": true, "enable": true,
                    "profile": .string(profile),
                ], timeout: .seconds(180))
            restart = restart || result["restart_required"]?.boolValue == true
            for old in replaced {
                // Most profiles never had one or the other: "not found" is fine.
                _ = try? await channel.call(
                    "plugins.manage", params: ["action": "remove", "name": .string(old), "profile": .string(profile)])
            }
        }
        return restart
    }

    /// Tells the plugin the app opened this chat, so its Bot hears it's talking through Usual Bot.
    static func noteChat(_ sessionID: String, on auth: AuthSession) async {
        struct Done: Decodable, Sendable {}
        let id = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionID
        // An older plugin has no such route; its chats just don't hear about the app.
        _ = try? await auth.json(Done.self, path: "\(path)/chats/\(id)", method: "PUT")
    }
}
