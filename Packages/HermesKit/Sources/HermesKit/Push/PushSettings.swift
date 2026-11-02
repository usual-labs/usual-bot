import Foundation
import Observation
import os

/// How the gateway reaches you when this app can't: ntfy or Pushover, through the `usual-push`
/// plugin (`Integrations/hermes-push`). Apple's own push would need a key only the app's signer
/// has, so each person brings their own service. The settings live on the gateway, which sends.
@MainActor
@Observable
public final class PushSettings {
    public enum Service: String, CaseIterable, Sendable {
        case off, ntfy, pushover
    }

    public enum Phase: Equatable, Sendable {
        case loading
        case ready
        /// The gateway doesn't have the plugin.
        case notInstalled
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public var service: Service = .off
    public var server = "https://ntfy.sh"
    public var topic = ""
    /// Whether the gateway holds these. None of them ever comes back to the app.
    public private(set) var hasNtfyToken = false
    public private(set) var hasToken = false
    public private(set) var hasUserKey = false
    /// A window has you, or the quick panel is open: agents' news can wait, here and on the gateway.
    public var isFocused: Bool { isWindowFocused || isPanelOpen }
    var isWindowFocused = false
    var isPanelOpen = false

    /// What the gateway should send, once a service is set up.
    public var isActive: Bool {
        guard phase == .ready else { return false }
        return switch service {
        case .off: false
        case .ntfy: !topic.isEmpty
        case .pushover: hasToken && hasUserKey
        }
    }

    private let auth: @MainActor () -> AuthSession?
    private var lastNames: [String: String]?
    private var reportedFocus: Bool?
    private var isReporting = false

    private static let path = "/api/plugins/usual-push"
    private static let log = Logger(subsystem: "UsualBot", category: "push")

    init(auth: @escaping @MainActor () -> AuthSession?) {
        self.auth = auth
    }

    private struct Wire: Codable, Sendable {
        var service: String
        var server: String?
        var topic: String?
        var message: Bool?
        var needsYou: Bool?
        var previews: Bool?
        var ntfyToken: String?
        var token: String?
        var userKey: String?
        var hasNtfyToken: Bool?
        var hasToken: Bool?
        var hasUserKey: Bool?
    }

    private struct Done: Decodable, Sendable {}

    public func refresh() async {
        guard let auth = auth() else { return }
        do {
            adopt(try await auth.json(Wire.self, path: "\(Self.path)/settings"))
        } catch GatewayError.http(status: 404, _) {
            phase = .notInstalled
        } catch {
            phase = .failed(AppModel.describe(error))
        }
    }

    /// What's in Settings and not on the gateway yet. Secrets left `nil` stay as they are.
    public struct Changes: Sendable {
        public var ntfyToken: String?
        public var token: String?
        public var userKey: String?
        public var messages: Bool
        public var needsYou: Bool
        public var previews: Bool

        public init(
            ntfyToken: String? = nil, token: String? = nil, userKey: String? = nil, messages: Bool, needsYou: Bool,
            previews: Bool
        ) {
            self.ntfyToken = ntfyToken
            self.token = token
            self.userKey = userKey
            self.messages = messages
            self.needsYou = needsYou
            self.previews = previews
        }
    }

    public func save(_ changes: Changes) async throws {
        guard let auth = auth() else { throw GatewayError.disconnected }
        let wire = Wire(
            service: service.rawValue, server: server, topic: topic, message: changes.messages,
            needsYou: changes.needsYou, previews: changes.previews, ntfyToken: changes.ntfyToken,
            token: changes.token, userKey: changes.userKey)
        adopt(try await auth.json(Wire.self, path: "\(Self.path)/settings", method: "PUT", body: wire))
    }

    /// Saves, then sends a test notification. The gateway sends through what it has saved, so a
    /// test of unsaved changes would go through the old service and still say it was sent.
    public func saveAndSendTest(_ changes: Changes) async throws {
        try await save(changes)
        guard let auth = auth() else { throw GatewayError.disconnected }
        _ = try await auth.json(Done.self, path: "\(Self.path)/test", method: "POST")
    }

    private func adopt(_ wire: Wire) {
        service = Service(rawValue: wire.service) ?? .off
        server = wire.server ?? server
        topic = wire.topic ?? ""
        hasNtfyToken = wire.hasNtfyToken ?? false
        hasToken = wire.hasToken ?? false
        hasUserKey = wire.hasUserKey ?? false
        phase = .ready
    }

    private struct Presence: Encodable, Sendable {
        let focused: Bool
        let names: [String: String]?
    }

    /// Tells the plugin whether you're at the app, so it holds its pushes, and the names to put in
    /// them. It forgets after a few seconds, so this repeats while you are. Out of focus it's said
    /// once: a Mac left running would otherwise keep overruling the iPhone in your hand.
    func report(names: [String: String]) async {
        let focused = isFocused
        let changed = names != lastNames
        guard isActive, !isReporting, focused || focused != reportedFocus || changed, let auth = auth() else { return }
        isReporting = true
        do {
            _ = try await auth.json(
                Done.self, path: "\(Self.path)/presence", method: "PUT",
                body: Presence(focused: focused, names: changed ? names : nil))
            lastNames = names
            reportedFocus = focused
        } catch {
            Self.log.error("Couldn't report focus: \(AppModel.describe(error), privacy: .public)")
        }
        isReporting = false
        // Leaving the app now can't wait for a next tick: iOS may not give it one.
        if focused != isFocused { await report(names: names) }
    }

    func clear() {
        phase = .loading
        service = .off
        topic = ""
        server = "https://ntfy.sh"
        hasNtfyToken = false
        hasToken = false
        hasUserKey = false
        lastNames = nil
        reportedFocus = nil
    }

    #if DEBUG
        /// The demo: as if ntfy were set up, with nowhere to send to.
        func showDemo() {
            service = .ntfy
            topic = "my-agents"
            phase = .ready
        }
    #endif
}
