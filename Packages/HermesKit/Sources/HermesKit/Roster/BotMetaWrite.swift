import Foundation

/// Saves a Bot's sidebar section on the gateway, in `ui_meta['hermes-bots']`.
enum BotMetaWrite {
    private static let key = "hermes-bots"
    private static let attempts = 3

    /// `profiles.configure` replaces the whole `hermes-bots` value, and the official app keeps more
    /// in it than Usual Bot decodes. So this reads the stored value raw, changes only the section,
    /// and sends it back guarded by its revision, trying again if something else wrote in between.
    static func setSection(_ placement: ContactPlacement, profile: String, on channel: JSONRPCChannel) async throws {
        for _ in 0..<attempts {
            let list = try await channel.call("profiles.list", params: ["include_sessions": false])
            guard case .array(let rows) = list["profiles"],
                let row = rows.first(where: { $0["name"]?.stringValue == profile })
            else { throw GatewayError.invalidResponse }

            var meta: [String: JSONValue] = [:]
            if case .object(let stored) = row["ui_meta"]?[key] { meta = stored }
            // The official app leaves this out of every write too.
            meta["chat"] = nil
            meta["sectionId"] = placement.id.map(JSONValue.string) ?? .null
            meta["sectionName"] = placement.name.map(JSONValue.string) ?? .null

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
