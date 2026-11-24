import Foundation
import Observation
import os

/// How the gateway reaches this device when the app can't: the `usual-bot` plugin
/// (`Integrations/usual-bot`, `UsualPlugin`) seals each notification for this device and hands it to Usual's
/// push relay (`PushRelay`). The gateway keeps this device's choices; the relay only its address.
@MainActor
@Observable
public final class PushSettings {
    public enum Phase: Equatable, Sendable {
        case loading
        case ready
        /// The gateway doesn't have the plugin.
        case notInstalled
        case failed(String)
    }

    /// What this device wants to hear about, from its notification settings.
    public struct Choices: Equatable, Sendable {
        public var messages = true
        public var needsYou = true
        public var previews = true
        public var sound = true

        public init(messages: Bool = true, needsYou: Bool = true, previews: Bool = true, sound: Bool = true) {
            self.messages = messages
            self.needsYou = needsYou
            self.previews = previews
            self.sound = sound
        }
    }

    public private(set) var phase: Phase = .loading
    /// The gateway has this device and pushes to it.
    public private(set) var isConnected = false
    /// Chats and rooms this device doesn't hear about. Everything else notifies.
    public private(set) var muted: Set<Contact.ID> = []
    /// The plugin seals which gateway sent each notification (0.5.0 and later, which say their
    /// version). An older one's notifications can't be told apart from another gateway's.
    public private(set) var tagsGateway = false
    /// The plugin's version, when it says. It's also `usual-push`'s from before the plugins merged.
    public private(set) var pluginVersion: String?
    /// The gateway has the plugin, but older than this build's: from before the merge, or before
    /// a change since.
    public var needsUpdate: Bool { phase == .ready && UsualPlugin.isOlder(pluginVersion) }
    /// Read when the gateway first meets this device. The app sets it.
    @ObservationIgnored public var currentChoices: @MainActor () -> Choices = { Choices() }
    /// A window has you, or the quick panel is open.
    public var isFocused: Bool { isWindowFocused || isPanelOpen }
    var isWindowFocused = false
    var isPanelOpen = false
    /// You've left this device alone a while, though the app is still in front. Tests set it.
    @ObservationIgnored var isAway: @MainActor () -> Bool = { UserIdle.isAway }

    /// The gateway pushes here, so this device's own alerts would say it twice.
    public var isActive: Bool { phase == .ready && isConnected }
    /// This build can push: it has a relay, and Apple gave it a token.
    public var isAvailable: Bool { relay()?.registration != nil }

    private let auth: @MainActor () -> AuthSession?
    private let relay: @MainActor () -> PushRelay?
    /// The gateway in use: its ID goes into what the plugin seals, and it says whether you want
    /// notifications from it.
    private let gateway: @MainActor () -> SavedGateway?
    private var lastNames: [String: String]?
    /// The chat last said to be in front; `.some(nil)` once "none" was said.
    private var reportedChat: Contact.ID??
    /// Whether this device was last said to be in use.
    private var reportedActive: Bool?
    private var isReporting = false
    private var isConnecting = false
    /// Changes stay here, as if the gateway took them.
    private var isDemo = false

    /// Where the plugin answers: `usual-bot`'s routes, or `usual-push`'s on a gateway that has
    /// the plugins from before they merged.
    private var path = UsualPlugin.path
    private static let log = Logger(subsystem: "UsualBot", category: "push")

    init(
        auth: @escaping @MainActor () -> AuthSession?, relay: @escaping @MainActor () -> PushRelay?,
        gateway: @escaping @MainActor () -> SavedGateway? = { nil }
    ) {
        self.auth = auth
        self.relay = relay
        self.gateway = gateway
    }

    private struct Device: Codable, Sendable {
        var id: String?
        var relay: String?
        var name: String?
        var platform: String?
        var sendKey: String?
        var sealKey: String?
        var message: Bool?
        var needsYou: Bool?
        var previews: Bool?
        var sound: Bool?
        var muted: [String]?
        /// Which of this device's gateways this is (`SavedGateway.id`).
        var gateway: String?
    }

    private struct Known: Decodable, Sendable {
        let devices: [Device]
        let version: String?
    }

    private struct Done: Decodable, Sendable {}

    public func refresh() async {
        if isDemo { return }
        guard let auth = auth() else { return }
        do {
            let known = try await settings(on: auth)
            let mine = relay()?.registration.flatMap { registration in
                known.devices.first { $0.id == registration.id }
            }
            tagsGateway = known.version != nil
            pluginVersion = known.version
            phase = .ready
            if gateway()?.notifies == false {
                // Turned off here: a device the gateway still has (a failed removal) goes now.
                isConnected = false
                if mine != nil { await forget(on: auth) }
                return
            }
            // A relay at a new address is told to the gateway again, choices and all, and so is
            // a device a newer plugin hasn't been told the gateway's ID.
            isConnected =
                mine != nil && mine?.relay == relay()?.address?.absoluteString
                && (!tagsGateway || mine?.gateway == gateway()?.id)
            muted = Set(mine?.muted ?? [])
        } catch GatewayError.http(status: 404, _) {
            phase = .notInstalled
        } catch {
            phase = .failed(AppModel.describe(error))
        }
        await connectIfNeeded()
    }

    private func settings(on auth: AuthSession) async throws -> Known {
        do {
            let known = try await auth.json(Known.self, path: "\(UsualPlugin.path)/settings")
            path = UsualPlugin.path
            return known
        } catch GatewayError.http(status: 404, _) {
            let known = try await auth.json(Known.self, path: "\(UsualPlugin.oldPushPath)/settings")
            path = UsualPlugin.oldPushPath
            return known
        }
    }

    /// Gives the gateway this device: where to reach it, the keys to do so, and its choices.
    func connectIfNeeded() async {
        guard phase == .ready, !isConnected, !isConnecting, !isDemo, gateway()?.notifies != false,
            let relay = relay(), let address = relay.address, let registration = relay.registration,
            let auth = auth()
        else { return }
        isConnecting = true
        defer { isConnecting = false }
        let choices = currentChoices()
        var device = Self.device(for: choices)
        device.relay = address.absoluteString
        device.name = Self.deviceName
        device.platform = Self.platform
        device.sendKey = registration.sendKey
        device.sealKey = registration.sealKey.base64EncodedString()
        device.gateway = gateway()?.id
        do {
            let saved = try await auth.json(
                Device.self, path: "\(path)/devices/\(registration.id)", method: "PUT", body: device)
            isConnected = true
            muted = Set(saved.muted ?? [])
        } catch {
            Self.log.error("Couldn't add this device to the gateway: \(AppModel.describe(error), privacy: .public)")
        }
    }

    public func save(_ choices: Choices) async throws {
        try await put(Self.device(for: choices))
    }

    /// Whether this device hears about a chat or room.
    public func setMuted(_ chat: Contact.ID, _ isMuted: Bool) async throws {
        var next = muted
        if isMuted { next.insert(chat) } else { next.remove(chat) }
        var device = Device()
        device.muted = next.sorted()
        try await put(device)
        muted = next
    }

    /// Asks the gateway to push a test to this device, the whole way: gateway, relay, Apple.
    public func sendTest() async throws {
        if isDemo { return }
        guard let auth = auth() else { throw GatewayError.disconnected }
        guard let registration = relay()?.registration else { throw PushError.notRegistered }
        _ = try await auth.json(
            Done.self, path: "\(path)/test", method: "POST", body: ["device": registration.id])
    }

    public enum PushError: LocalizedError {
        case notRegistered

        public var errorDescription: String? {
            String(localized: "This device hasn’t signed up for notifications yet.")
        }
    }

    private func put(_ device: Device) async throws {
        if isDemo { return }
        guard let auth = auth() else { throw GatewayError.disconnected }
        guard let registration = relay()?.registration else { throw PushError.notRegistered }
        let saved = try await auth.json(
            Device.self, path: "\(path)/devices/\(registration.id)", method: "PUT", body: device)
        muted = Set(saved.muted ?? [])
    }

    private static func device(for choices: Choices) -> Device {
        var device = Device()
        device.message = choices.messages
        device.needsYou = choices.needsYou
        device.previews = choices.previews
        device.sound = choices.sound
        return device
    }

    private struct Presence: Encodable, Sendable {
        let device: String
        let chat: String?
        let active: Bool
        let names: [String: String]?
    }

    /// Tells the gateway which chat you're reading here, so no device hears about it, and whether
    /// you're using this device, so it hears first and your others a little later. The gateway
    /// forgets both after a few seconds, so this repeats while either holds. Leaving is said once.
    func report(visible: Contact.ID?, names: [String: String]) async {
        await connectIfNeeded()
        let chat = isFocused ? visible : nil
        let active = isFocused && !isAway()
        let changed = names != lastNames
        guard isActive, !isReporting,
            chat != nil || active || reportedChat != .some(chat) || reportedActive != active || changed,
            let registration = relay()?.registration, let auth = auth()
        else { return }
        isReporting = true
        do {
            _ = try await auth.json(
                Done.self, path: "\(path)/presence", method: "PUT",
                body: Presence(device: registration.id, chat: chat, active: active, names: changed ? names : nil))
            lastNames = names
            reportedChat = .some(chat)
            reportedActive = active
        } catch {
            Self.log.error("Couldn't report the open chat: \(AppModel.describe(error), privacy: .public)")
        }
        isReporting = false
    }

    /// You left this gateway for another, so you're reading none of its chats: said straight away,
    /// as the app stops reporting to it.
    func reportNoneOpen(on auth: AuthSession) async {
        guard !isDemo, let registration = relay()?.registration else { return }
        do {
            _ = try await auth.json(
                Done.self, path: "\(path)/presence", method: "PUT",
                body: Presence(device: registration.id, chat: nil, active: false, names: nil))
        } catch {
            Self.log.error("Couldn't say no chat is open: \(AppModel.describe(error), privacy: .public)")
        }
    }

    /// Takes this device off the gateway, or it would keep hearing about a gateway it signed out of.
    func forget(on auth: AuthSession) async {
        guard !isDemo, let registration = relay()?.registration else { return }
        do {
            _ = try await auth.json(Done.self, path: "\(path)/devices/\(registration.id)", method: "DELETE")
        } catch {
            Self.log.error("Couldn't take this device off the gateway: \(AppModel.describe(error), privacy: .public)")
        }
    }

    func clear() {
        phase = .loading
        isConnected = false
        muted = []
        tagsGateway = false
        pluginVersion = nil
        path = UsualPlugin.path
        lastNames = nil
        reportedChat = nil
        reportedActive = nil
    }

    private static var platform: String {
        #if os(macOS)
            "mac"
        #else
            "iphone"
        #endif
    }

    private static var deviceName: String {
        #if os(macOS)
            Host.current().localizedName ?? "Mac"
        #else
            "iPhone"
        #endif
    }

    #if DEBUG
        /// The demo: as if the gateway pushed here, with nowhere to send to.
        func showDemo() {
            phase = .ready
            isConnected = true
            tagsGateway = true
            // USUALBOT_DEMO_PLUGIN_UPDATE=1: the gateway has an older plugin, so the Mac sidebar's
            // Plugins button shows its update dot and the sheet offers Update.
            let older = ProcessInfo.processInfo.environment["USUALBOT_DEMO_PLUGIN_UPDATE"] == "1"
            pluginVersion = older ? "0.1.0" : UsualPlugin.version
            isDemo = true
        }
    #endif
}
