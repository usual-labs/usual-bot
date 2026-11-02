import Foundation

/// Saves a Bot's own settings on the gateway, in `ui_meta['hermes-bots']`: its sidebar section,
/// its name and what kind of picture it has.
enum BotMetaWrite {
    private static let key = "hermes-bots"
    private static let attempts = 3

    static func setSection(_ placement: ContactPlacement, profile: String, on channel: JSONRPCChannel) async throws {
        try await update(profile: profile, on: channel) { meta in
            meta["sectionId"] = placement.id.map(JSONValue.string) ?? .null
            meta["sectionName"] = placement.name.map(JSONValue.string) ?? .null
        }
    }

    /// The Bot's name, as the official app's Edit Profile saves it. An empty name goes back to the
    /// one Hermes gives the profile.
    static func setTitle(_ title: String, profile: String, on channel: JSONRPCChannel) async throws {
        try await update(profile: profile, on: channel) { $0["title"] = .string(title) }
    }

    /// Marks the picture as one the user chose (`photo`) or none (`shape`, the drawn face), as the
    /// official app does beside `profiles.set_asset`. The write also gives the Bot a new revision,
    /// which is how every app learns to read its picture again.
    static func setPictureKind(isPhoto: Bool, profile: String, on channel: JSONRPCChannel) async throws {
        try await update(profile: profile, on: channel) { $0["imageKind"] = .string(isPhoto ? "photo" : "shape") }
    }

    /// `profiles.configure` replaces the whole `hermes-bots` value, and the official app keeps more
    /// in it than Usual Bot decodes. So this reads the stored value raw, applies `change`, and sends
    /// it back guarded by its revision, trying again if something else wrote in between.
    private static func update(
        profile: String, on channel: JSONRPCChannel, change: (inout [String: JSONValue]) -> Void
    ) async throws {
        for _ in 0..<attempts {
            let list = try await channel.call("profiles.list", params: ["include_sessions": false])
            guard case .array(let rows) = list["profiles"],
                let row = rows.first(where: { $0["name"]?.stringValue == profile })
            else { throw GatewayError.invalidResponse }

            var meta: [String: JSONValue] = [:]
            if case .object(let stored) = row["ui_meta"]?[key] { meta = stored }
            // The official app leaves this out of every write too.
            meta["chat"] = nil
            change(&meta)

            var params: [String: JSONValue] = ["name": .string(profile), "ui_meta": [key: .object(meta)]]
            // An older gateway reports no revisions, and takes the write unguarded.
            if case .object(let revisions) = row["ui_meta_revisions"] {
                let revision = max(revisions[key]?.intValue ?? 0, 0)
                params["ui_meta_expected_revisions"] = [key: .number(Double(revision))]
            }

            let result = try await channel.call("profiles.configure", params: .object(params))
            if result["applied"]?["ui_meta_conflicts"] != nil { continue }
            guard result["applied"]?["ui_meta"]?.boolValue == true else {
                throw GatewayError.rpc(
                    code: 0, message: String(localized: "The gateway didn't save it. Update Hermes and try again."))
            }
            return
        }
        throw GatewayError.rpc(
            code: 0, message: String(localized: "This Bot was changing somewhere else at the same time. Try again."))
    }
}
