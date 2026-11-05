import Foundation
import Observation
import os

/// How the gateway reaches this device when the app can't: the `usual-push` plugin
/// (`Integrations/hermes-push`) seals each notification for this device and hands it to Usual's
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
    /// Read when the gateway first meets this device. The app sets it.
    @ObservationIgnored public var currentChoices: @MainActor () -> Choices = { Choices() }
    /// A window has you, or the quick panel is open.
    public var isFocused: Bool { isWindowFocused || isPanelOpen }
    var isWindowFocused = false
    var isPanelOpen = false

    /// The gateway pushes here, so this device's own alerts would say it twice.
    public var isActive: Bool { phase == .ready && isConnected }
    /// This build can push: it has a relay, and Apple gave it a token.
    public var isAvailable: Bool { relay()?.registration != nil }

    private let auth: @MainActor () -> AuthSession?
    private let relay: @MainActor () -> PushRelay?
    private var lastNames: [String: String]?
    /// The chat last said to be in front; `.some(nil)` once "none" was said.
    private var reportedChat: Contact.ID??
    private var isReporting = false
    private var isConnecting = false
    /// Changes stay here, as if the gateway took them.
    private var isDemo = false

    private static let path = "/api/plugins/usual-push"
    private static let log = Logger(subsystem: "UsualBot", category: "push")

    init(auth: @escaping @MainActor () -> AuthSession?, relay: @escaping @MainActor () -> PushRelay?) {
        self.auth = auth
        self.relay = relay
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
    }

    private struct Known: Decodable, Sendable {
        let devices: [Device]
    }

    private struct Done: Decodable, Sendable {}

    public func refresh() async {
        if isDemo { return }
        guard let auth = auth() else { return }
        do {
            let known = try await auth.json(Known.self, path: "\(Self.path)/settings")
            let mine = relay()?.registration.flatMap { registration in
                known.devices.first { $0.id == registration.id }
            }
            // A relay at a new address is told to the gateway again, choices and all.
            isConnected = mine != nil && mine?.relay == relay()?.address?.absoluteString
            muted = Set(mine?.muted ?? [])
            phase = .ready
        } catch GatewayError.http(status: 404, _) {
            phase = .notInstalled
        } catch {
            phase = .failed(AppModel.describe(error))
        }
        await connectIfNeeded()
    }

    /// Gives the gateway this device: where to reach it, the keys to do so, and its choices.
    func connectIfNeeded() async {
        guard phase == .ready, !isConnected, !isConnecting, !isDemo,
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
        do {
            let saved = try await auth.json(
                Device.self, path: "\(Self.path)/devices/\(registration.id)", method: "PUT", body: device)
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
            Done.self, path: "\(Self.path)/test", method: "POST", body: ["device": registration.id])
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
            Device.self, path: "\(Self.path)/devices/\(registration.id)", method: "PUT", body: device)
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
        let names: [String: String]?
    }

    /// Tells the gateway which chat you're reading here, so no device hears about it. It forgets
    /// after a few seconds, so this repeats while one is open. "None" is said once: a Mac left
    /// running would otherwise keep overruling the iPhone in your hand.
    func report(visible: Contact.ID?, names: [String: String]) async {
        await connectIfNeeded()
        let chat = isFocused ? visible : nil
        let changed = names != lastNames
        guard isActive, !isReporting, chat != nil || reportedChat != .some(chat) || changed,
            let registration = relay()?.registration, let auth = auth()
        else { return }
        isReporting = true
        do {
            _ = try await auth.json(
                Done.self, path: "\(Self.path)/presence", method: "PUT",
                body: Presence(device: registration.id, chat: chat, names: changed ? names : nil))
            lastNames = names
            reportedChat = .some(chat)
        } catch {
            Self.log.error("Couldn't report the open chat: \(AppModel.describe(error), privacy: .public)")
        }
        isReporting = false
    }

    /// Takes this device off the gateway, or it would keep hearing about a gateway it signed out of.
    func forget(on auth: AuthSession) async {
        guard !isDemo, let registration = relay()?.registration else { return }
        do {
            _ = try await auth.json(Done.self, path: "\(Self.path)/devices/\(registration.id)", method: "DELETE")
        } catch {
            Self.log.error("Couldn't take this device off the gateway: \(AppModel.describe(error), privacy: .public)")
        }
    }

    func clear() {
        phase = .loading
        isConnected = false
        muted = []
        lastNames = nil
        reportedChat = nil
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
            isDemo = true
        }
    #endif
}
