import Foundation
import Observation

/// One agent's credential vault on the gateway: what's saved, as metadata, and its password
/// managers. Every call names the profile: without it the gateway would use its launch profile.
/// Never cached: this stays in memory, and the gateway never sends a secret back.
@MainActor
@Observable
public final class VaultList {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// The Hermes profile the vault belongs to.
    public let profile: String
    public private(set) var items: [VaultItem] = []
    public private(set) var sources: [VaultSource] = []
    public private(set) var phase: Phase = .loading
    /// The last action that didn't go through, with any secret taken out.
    public private(set) var problem: String?

    /// A password manager's own tool gets 30 s on the gateway, and a call there waits its turn.
    private static let unlockTimeout = Duration.seconds(45)

    private let channel: @MainActor () -> JSONRPCChannel?
    private let gatewayIsUnencrypted: @MainActor () -> Bool
    private var refreshing = false

    init(
        profile: String, channel: @escaping @MainActor () -> JSONRPCChannel?,
        gatewayIsUnencrypted: @escaping @MainActor () -> Bool
    ) {
        self.profile = profile
        self.channel = channel
        self.gatewayIsUnencrypted = gatewayIsUnencrypted
    }

    /// Password managers, without the Hermes vault itself, which is always on.
    public var managers: [VaultSource] { sources.filter(\.needsUnlock) }

    /// Secrets would cross the network unencrypted, so they need your say-so each time.
    public var isUnencrypted: Bool { gatewayIsUnencrypted() }

    /// Reloads the list. Keeps showing the old one if the reload fails.
    public func refresh() async {
        guard !refreshing else { return }
        guard let channel = channel() else {
            if phase != .ready { phase = .failed(Self.message(for: GatewayError.disconnected)) }
            return
        }
        refreshing = true
        defer { refreshing = false }
        struct Listing: Decodable { let items: [VaultItem] }
        struct Sources: Decodable { let sources: [VaultSource] }
        do {
            let listing = try await channel.call("vault.list", params: scope())
            let status = try await channel.call("vault.sources", params: scope())
            guard let listed = try? listing.decode(Listing.self), let managers = try? status.decode(Sources.self)
            else { throw GatewayError.invalidResponse }
            items = listed.items
            sources = managers.sources
            phase = .ready
        } catch {
            if phase != .ready { phase = .failed(Self.message(for: error)) }
        }
    }

    /// Saves a new item. Returns whether it was saved; if not, `problem` says why and the caller
    /// keeps the form. On an unencrypted address nothing goes out without `allowingUnencrypted`.
    public func add(_ draft: VaultDraft, allowingUnencrypted: Bool = false) async -> Bool {
        guard draft.isComplete, allowingUnencrypted || !isUnencrypted else { return false }
        problem = nil
        do {
            _ = try await connected().call("vault.add", params: scope(draft.params), sensitive: true)
            await refresh()
            return true
        } catch {
            problem = Self.message(for: error, removing: draft.secretValues)
            return false
        }
    }

    /// Removes an item from the Hermes vault for good.
    public func remove(_ item: VaultItem) async {
        guard item.isRemovable else { return }
        problem = nil
        do {
            let result = try await connected().call("vault.remove", params: scope(["id": .string(item.id)]))
            items.removeAll { $0.id == item.id }
            if result["removed"]?.boolValue != true {
                problem = String(localized: "“\(item.label)” was already gone.")
            }
        } catch {
            problem = String(localized: "Couldn't remove “\(item.label)”: \(Self.message(for: error))")
        }
    }

    /// Turns a password manager on or off. The switch moves at once and moves back if the gateway
    /// refuses. Turning one off also locks it.
    public func setEnabled(_ enabled: Bool, for source: VaultSource) async {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        problem = nil
        sources[index].enabled = enabled
        do {
            let params = scope(["name": .string(source.name), "enabled": .bool(enabled)])
            _ = try await connected().call("vault.source.set", params: params)
            await refresh()
        } catch {
            if let current = sources.firstIndex(where: { $0.id == source.id }) { sources[current].enabled = !enabled }
            problem = String(localized: "Couldn't change \(source.displayName): \(Self.message(for: error))")
        }
    }

    /// Unlocks a password manager with its master password, which the gateway passes to the
    /// manager's own tool and doesn't keep. Returns whether it worked; if not, `problem` says why.
    /// On an unencrypted address nothing goes out without `allowingUnencrypted`.
    public func unlock(_ source: VaultSource, password: String, allowingUnencrypted: Bool = false) async -> Bool {
        guard !password.isEmpty, allowingUnencrypted || !isUnencrypted else { return false }
        problem = nil
        do {
            _ = try await connected().call(
                "vault.unlock", params: scope(["name": .string(source.name), "password": .string(password)]),
                timeout: Self.unlockTimeout, sensitive: true)
            await refresh()
            return true
        } catch {
            problem = String(
                localized: "Couldn't unlock \(source.displayName): \(Self.message(for: error, removing: [password]))")
            return false
        }
    }

    /// Makes the gateway forget a password manager's session.
    public func lock(_ source: VaultSource) async {
        problem = nil
        do {
            _ = try await connected().call("vault.lock", params: scope(["name": .string(source.name)]))
            await refresh()
        } catch {
            problem = String(localized: "Couldn't lock \(source.displayName): \(Self.message(for: error))")
        }
    }

    private func connected() throws -> JSONRPCChannel {
        guard let channel = channel() else { throw GatewayError.disconnected }
        return channel
    }

    private func scope(_ params: [String: JSONValue] = [:]) -> JSONValue {
        .object(params.merging(["profile": .string(profile)]) { $1 })
    }

    /// An error in words for the UI, with no secret in it.
    private static func message(for error: any Error, removing secrets: [String] = []) -> String {
        if case .rpc(-32601, _) = error as? GatewayError {
            return String(localized: "This gateway's Hermes has no credential vault. Update Hermes on it.")
        }
        return VaultRedaction.scrub(AppModel.describe(error), removing: secrets)
    }

    #if DEBUG
        /// Tests and previews: a list already showing `items`. Nothing can reach a gateway from it.
        public static func sample(items: [VaultItem], sources: [VaultSource] = []) -> VaultList {
            let list = VaultList(profile: "sample", channel: { nil }, gatewayIsUnencrypted: { false })
            list.items = items
            list.sources = sources
            list.phase = .ready
            return list
        }
    #endif
}
