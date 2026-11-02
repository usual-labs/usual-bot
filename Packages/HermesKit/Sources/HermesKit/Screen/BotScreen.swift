import CoreGraphics
import CryptoKit
import Foundation
import Observation

/// Who drives an agent's screen. `viewerHash` names the person in control without giving away
/// their viewer ID, which is a capability.
public struct DisplayLease: Decodable, Equatable, Sendable {
    public enum Holder: String, Decodable, Sendable { case agent, human }

    public let holder: Holder
    public let viewerHash: String?
    public let epoch: Int
    /// What the agent asked for, when it asked someone to take over.
    public let reason: String?

    public init(holder: Holder, viewerHash: String? = nil, epoch: Int = 0, reason: String? = nil) {
        self.holder = holder
        self.viewerHash = viewerHash
        self.epoch = epoch
        self.reason = reason
    }
}

/// `display.status`: whether the agent's profile has a screen (a headless Linux desktop on the
/// gateway host or in its sandbox), whether it's on, and who drives it.
public struct DisplayStatus: Decodable, Equatable, Sendable {
    public let supported: Bool
    public let installed: Bool
    public let running: Bool
    public let geometry: String?
    /// Why it can't start now, in Hermes's words.
    public let blocker: String?
    public let lease: DisplayLease?
    /// Names the profile in `display.*` events.
    public let profileKey: String?

    public init(
        supported: Bool, installed: Bool, running: Bool, geometry: String? = nil, blocker: String? = nil,
        lease: DisplayLease? = nil, profileKey: String? = nil
    ) {
        self.supported = supported
        self.installed = installed
        self.running = running
        self.geometry = geometry
        self.blocker = blocker
        self.lease = lease
        self.profileKey = profileKey
    }
}

public typealias ScreenSocketFactory = @Sendable (URL) async throws -> any ScreenSocket

/// One agent's computer: its screen streamed live over RFB, and Take over through the lease.
/// `display.*` calls ride the app's socket; the picture comes on its own WebSocket, opened with a
/// single-use ticket from `display.observe`.
@MainActor
@Observable
public final class BotScreen {
    public enum Connection: Equatable {
        case idle, connecting, live
        case failed(String)
    }

    public enum Control: Equatable { case agent, you, someoneElse }

    public let profile: String
    public private(set) var status: DisplayStatus?
    public private(set) var lease: DisplayLease?
    public private(set) var connection = Connection.idle
    /// The screen as last drawn, and its size in pixels.
    public private(set) var frame: CGImage?
    public private(set) var frameSize = CGSize.zero
    /// Something that happened to you, such as someone else taking control.
    public private(set) var notice: String?
    /// The last start, take over or hand back that failed.
    public private(set) var problem: String?
    /// Starting, taking over or handing back.
    public private(set) var isBusy = false
    /// This app's viewer, as the lease names it.
    private var viewerHash: String?

    @ObservationIgnored private let channel: @MainActor () -> JSONRPCChannel?
    @ObservationIgnored private let gateway: @MainActor () -> GatewayAddress?
    @ObservationIgnored private let makeSocket: ScreenSocketFactory
    @ObservationIgnored private var viewerID: String?
    @ObservationIgnored private var client: RFBClient?
    @ObservationIgnored private var socket: (any ScreenSocket)?
    @ObservationIgnored private var stream: Task<Void, Never>?
    @ObservationIgnored private var staleTickets = 0
    @ObservationIgnored var isDemo = false

    init(
        profile: String, channel: @escaping @MainActor () -> JSONRPCChannel?,
        gateway: @escaping @MainActor () -> GatewayAddress?, makeSocket: @escaping ScreenSocketFactory
    ) {
        self.profile = profile
        self.channel = channel
        self.gateway = gateway
        self.makeSocket = makeSocket
    }

    /// The agent has a screen you could watch: the chat shows its way in.
    public var hasScreen: Bool { status.map { $0.supported && $0.installed } ?? false }

    /// Plain `http` off this device: what you type on the screen could be read on the way.
    public var isUnencrypted: Bool { gateway()?.isUnencrypted ?? false }

    public var control: Control {
        guard let lease, lease.holder == .human else { return .agent }
        return lease.viewerHash != nil && lease.viewerHash == viewerHash ? .you : .someoneElse
    }

    // MARK: - Status

    /// Reads `display.status`. A Hermes without `display.*` has no screen to show.
    public func refresh() async {
        guard !isDemo, let channel = channel() else { return }
        do {
            apply(
                try await channel.call("display.status", params: ["profile": .string(profile)]).decode(
                    DisplayStatus.self))
        } catch GatewayError.rpc(let code, _) where code == -32601 {
            status = DisplayStatus(supported: false, installed: false, running: false)
        } catch {}
    }

    /// Turns the screen on (`display.start`), then shows it.
    public func start() async {
        await act {
            let reply = try await $0.call(
                "display.start", params: ["profile": .string(self.profile)], timeout: .seconds(90))
            self.apply(try reply.decode(DisplayStatus.self))
        }
        if status?.running == true { connect() }
    }

    private func apply(_ next: DisplayStatus) {
        status = next
        if let lease = next.lease { take(lease) }
        if !next.running, connection != .idle { disconnect() }
    }

    /// A lease no older than the one shown.
    private func take(_ next: DisplayLease) {
        guard next.epoch >= (lease?.epoch ?? .min) else { return }
        lease = next
    }

    /// `display.status` and `display.lease` from the gateway, for any profile.
    func apply(_ event: GatewayEvent) {
        guard let key = event.payload["profile_key"]?.stringValue, key == status?.profileKey else { return }
        switch event.type {
        case "display.lease":
            if let lease = try? event.payload["lease"]?.decode(DisplayLease.self) { take(lease) }
        case "display.status":
            if let status = try? event.payload.decode(DisplayStatus.self) { apply(status) }
        default:
            break
        }
    }

    // MARK: - Watching

    /// Opens the live picture. Safe to call again: it starts over.
    public func connect() {
        guard !isDemo else { return }
        stopStream()
        notice = nil
        connection = .connecting
        stream = Task { await self.watch() }
    }

    /// Closes the picture. Closing hands control back if you had it.
    public func disconnect() {
        stopStream()
        connection = .idle
    }

    /// The app's socket was replaced, so viewer IDs it was given no longer count: start over to get a
    /// new one, keeping control if you had it.
    func linkChanged() {
        if connection != .idle { connect() }
    }

    private func stopStream() {
        stream?.cancel()
        stream = nil
        socket?.close()
        socket = nil
        client = nil
    }

    private func watch() async {
        do {
            guard let channel = channel(), let gateway = gateway() else { throw GatewayError.disconnected }
            let previousHash = viewerHash
            var params: [String: JSONValue] = ["profile": .string(profile)]
            if let viewerID { params["viewer_id"] = .string(viewerID) }
            let reply = try await channel.call("display.observe", params: .object(params))
            try Task.checkCancellation()
            guard let ticket = reply["ticket"]?.stringValue, let id = reply["viewer_id"]?.stringValue else {
                throw GatewayError.invalidResponse
            }
            let path = reply["path"]?.stringValue.flatMap { $0.hasPrefix("/api/") ? $0 : nil } ?? "/api/display/ws"
            viewerID = id
            viewerHash = Self.hash(id)
            if let status = try? reply.decode(DisplayStatus.self) { apply(status) }
            // A new socket mints a new viewer: carry control over if the old one had it.
            if let previousHash, previousHash != viewerHash, lease?.holder == .human, lease?.viewerHash == previousHash
            {
                _ = try? await acquire(on: channel)
            }
            let socket = try await makeSocket(gateway.screenSocketURL(path: path, ticket: ticket))
            try Task.checkCancellation()
            self.socket = socket
            let client = RFBClient(socket: socket)
            self.client = client
            show(try await client.handshake())
            connection = .live
            staleTickets = 0
            while !Task.isCancelled { show(try await client.nextFrame()) }
        } catch {
            guard !Task.isCancelled else { return }
            ended(by: error)
        }
    }

    private func show(_ framebuffer: Framebuffer) {
        frame = framebuffer.image()
        frameSize = CGSize(width: framebuffer.width, height: framebuffer.height)
    }

    private func ended(by error: any Error) {
        socket = nil
        client = nil
        switch (error as? ScreenSocketClosed)?.code {
        case 4000:
            connect()
            notice = String(localized: "Someone else took control. You're watching.")
        case 4001:
            connection = .idle
            Task { await refresh() }
        case 4401 where staleTickets < 2:
            staleTickets += 1
            connect()
        case 4403:
            connection = .failed(String(localized: "The gateway refused the screen's connection."))
        default:
            if let failure = error as? RFBClient.Failure, case .refused(let reason) = failure, !reason.isEmpty {
                connection = .failed(String(localized: "The computer refused the connection: \(reason)"))
            } else if error is ScreenSocketClosed || error is RFBClient.Failure || error is ZRLEDecoder.Failure {
                connection = .failed(String(localized: "Lost the connection to the computer."))
            } else {
                connection = .failed(AppModel.describe(error))
            }
        }
    }

    // MARK: - Control

    /// Takes control from the agent, or from whoever has it.
    public func takeOver() async {
        if isDemo {
            lease = DisplayLease(holder: .human, viewerHash: viewerHash, epoch: (lease?.epoch ?? 0) + 1)
            return
        }
        await act { _ = try await self.acquire(on: $0) }
    }

    /// Gives control back to the agent.
    public func handBack() async {
        if isDemo {
            lease = DisplayLease(holder: .agent, epoch: (lease?.epoch ?? 0) + 1)
            return
        }
        await act { channel in
            var params: [String: JSONValue] = ["profile": .string(self.profile)]
            if let viewerID = self.viewerID { params["viewer_id"] = .string(viewerID) }
            do {
                self.take(try Self.lease(in: await channel.call("display.lease.release", params: .object(params))))
            } catch GatewayError.rpc where self.control == .you {
                // Our viewer is from an earlier socket; the lease is still ours by its hash.
                params["force"] = true
                self.take(try Self.lease(in: await channel.call("display.lease.release", params: .object(params))))
            }
        }
    }

    private func acquire(on channel: JSONRPCChannel) async throws {
        guard let viewerID else { throw GatewayError.disconnected }
        let reply = try await channel.call(
            "display.lease.acquire", params: ["profile": .string(profile), "viewer_id": .string(viewerID)])
        take(try Self.lease(in: reply))
        notice = nil
    }

    private static func lease(in reply: JSONValue) throws -> DisplayLease {
        guard let lease = reply["lease"] else { throw GatewayError.invalidResponse }
        return try lease.decode(DisplayLease.self)
    }

    private func act(_ work: @escaping @MainActor (JSONRPCChannel) async throws -> Void) async {
        guard !isBusy else { return }
        guard let channel = channel() else {
            problem = GatewayError.disconnected.errorDescription
            return
        }
        isBusy = true
        problem = nil
        defer { isBusy = false }
        do {
            try await work(channel)
        } catch {
            problem = AppModel.describe(error)
        }
    }

    // MARK: - Input

    /// Moves the pointer to (`x`, `y`) in screen pixels with `buttons` held (1 left, 2 middle,
    /// 4 right, 8 and 16 scroll up and down). Ignored unless you're in control.
    public func pointer(x: Double, y: Double, buttons: UInt8) {
        guard control == .you, let client else { return }
        let px = Int(x.rounded(.down))
        let py = Int(y.rounded(.down))
        Task { try? await client.pointer(x: px, y: py, buttons: buttons) }
    }

    /// Presses or releases a key by its X keysym (`Keysym`).
    public func key(_ keysym: UInt32, down: Bool) {
        guard control == .you, let client else { return }
        Task { try? await client.key(keysym, down: down) }
    }

    /// Types `text`, one key press per character.
    public func type(_ text: String) {
        guard control == .you, let client else { return }
        let keys = text.compactMap(Keysym.init(character:))
        Task {
            for key in keys {
                try? await client.key(key.value, down: true)
                try? await client.key(key.value, down: false)
            }
        }
    }

    // MARK: -

    static func hash(_ viewerID: String) -> String {
        SHA256.hash(data: Data(viewerID.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    #if DEBUG
        /// The demo's computer: a made-up desktop the agent is using.
        static func demo(profile: String) -> BotScreen {
            let screen = BotScreen(
                profile: profile, channel: { nil }, gateway: { nil },
                makeSocket: { _ in
                    throw GatewayError.disconnected
                })
            screen.isDemo = true
            screen.viewerHash = "demo"
            screen.status = DisplayStatus(
                supported: true, installed: true, running: true, geometry: "1440x900",
                lease: DisplayLease(holder: .agent))
            screen.lease = screen.status?.lease
            screen.show(DemoDesktop.framebuffer())
            screen.connection = .live
            return screen
        }
    #endif
}

extension GatewayAddress {
    /// The screen's RFB socket, authenticated by `display.observe`'s single-use ticket alone.
    func screenSocketURL(path: String, ticket: String) -> URL {
        var components = URLComponents(url: url(path), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "display_ticket", value: ticket)]
        return components.url!
    }
}

extension ThreadState {
    /// The running turn is acting on the agent's screen right now.
    public var isUsingComputer: Bool {
        guard isRunning, case .activity(let steps) = items.last?.content else { return false }
        return steps.contains { $0.state == .running && $0.name == "computer_use" }
    }
}
