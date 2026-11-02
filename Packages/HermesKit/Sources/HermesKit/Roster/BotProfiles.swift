import Foundation

/// Making and removing Bots on the gateway: a Bot is a Hermes profile. Read from Hermes
/// `bf0203a794`: `profiles.create` and `profiles.set_asset` are on the dashboard socket
/// (`tui_gateway/methods_profiles.py`); deleting is only `DELETE /api/profiles/{name}`
/// (`hermes_cli/web_routers/profiles.py`).
enum BotProfiles {
    /// Creates the profile the way the official app's New Bot does with nothing changed under
    /// Advanced, except that it starts fresh rather than as a copy of `default`: Hermes's bundled
    /// skills, the gateway's own model and provider keys (`mirror_credentials`, on by default) and
    /// its sign-ins shared rather than copied (`share_auth`), and a short SOUL.md that tells the
    /// agent its name. Returns the profile name.
    static func create(_ name: BotName, description: String?, on channel: JSONRPCChannel) async throws -> String {
        var params: [String: JSONValue] = [
            "name": .string(name.profile), "share_auth": true,
            "soul": .string(soul(for: name, description: description)),
        ]
        if let description { params["description"] = .string(description) }
        let result = try await channel.call("profiles.create", params: .object(params))
        return result["name"]?.stringValue ?? name.profile
    }

    /// The official app's starting SOUL.md (`composeSoul` with no SOUL of its own), less the
    /// messaging section the gateway now adds by itself (`bot_mode_protocol`).
    static func soul(for name: BotName, description: String?) -> String {
        var lines = ["# \(name.title)", ""]
        if let description { lines += ["**Mission:** \(description)", ""] }
        lines += [
            "You are \(name.title), a persistent named agent (profile `\(name.profile)`) on this machine.",
            "You keep your own memory, skills, and conversation history across sessions.",
        ]
        return lines.joined(separator: "\n")
    }

    /// Whether the new profile has a model it can reply with. `nil` when the gateway can't say.
    static func canReply(profile: String, on channel: JSONRPCChannel) async -> Bool? {
        let result = try? await channel.call("setup.runtime_check", params: ["profile": .string(profile)])
        return result?["ok"]?.boolValue
    }

    /// Stores `png` (from `BotPictureFile.prepare`) as the Bot's picture, then marks it a photo, which
    /// gives the Bot a new revision so every app reads the picture again.
    static func setPicture(_ png: Data, profile: String, on channel: JSONRPCChannel) async throws {
        _ = try await channel.call(
            "profiles.set_asset",
            params: [
                "name": .string(profile), "asset": "avatar",
                "data": .string("data:image/png;base64,\(png.base64EncodedString())"),
            ])
        try await BotMetaWrite.setPictureKind(isPhoto: true, profile: profile, on: channel)
    }

    /// Removes the Bot's picture, so apps draw its face again.
    static func removePicture(profile: String, on channel: JSONRPCChannel) async throws {
        _ = try await channel.call(
            "profiles.set_asset", params: ["name": .string(profile), "asset": "avatar", "clear": true])
        try await BotMetaWrite.setPictureKind(isPhoto: false, profile: profile, on: channel)
    }

    /// Deletes the profile and everything in its folder. Hermes stops the Bot's gateway first, which
    /// can take ten seconds, then removes the folder, hence the long wait.
    static func delete(profile: String, auth: AuthSession) async throws {
        struct Reply: Decodable { let ok: Bool? }
        let name = profile.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? profile
        // "Settlement pending" still answers ok: the folder is gone either way.
        _ = try await auth.json(Reply.self, path: "/api/profiles/\(name)", method: "DELETE", timeout: 120)
    }
}
