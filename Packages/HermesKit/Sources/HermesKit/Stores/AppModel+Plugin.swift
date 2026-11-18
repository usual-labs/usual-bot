import Foundation

extension AppModel {
    /// Installs the `usual-bot` plugin into every Bot, hidden ones included, or updates it there,
    /// with Hermes's own installer (`plugins.manage`), then asks the gateway again what it has.
    /// True when the gateway has to restart before the plugin runs.
    public func installPlugin() async throws -> Bool {
        if isDemo { return false }
        guard let channel else { throw GatewayError.disconnected }
        let list = try await channel.call("profiles.list", params: ["include_sessions": false])
        guard case .array(let rows) = list["profiles"] else { throw GatewayError.invalidResponse }
        let restart = try await UsualPlugin.install(
            profiles: rows.compactMap { $0["name"]?.stringValue }, on: channel)
        await refreshPlugin()
        return restart
    }

    /// A Bot made here gets the plugin when the gateway's other Bots have this build's, as
    /// `install-usual-bot.sh` gives it to every profile. With an older one there, Settings › Plugins
    /// offers Update, which covers this Bot too.
    func installPlugin(into profile: String, on channel: JSONRPCChannel) async {
        guard push.phase == .ready, !push.needsUpdate else { return }
        try? await UsualPlugin.install(profiles: [profile], on: channel)
    }

    private func refreshPlugin() async {
        await push.refresh()
        for bot in contacts where bot.kind == .agent { await browser(for: bot).refresh() }
    }
}
