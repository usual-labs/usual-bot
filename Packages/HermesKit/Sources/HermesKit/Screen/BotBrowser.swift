import CoreGraphics
import Foundation
import ImageIO
import Observation

/// An agent's browser, live: the headless Chrome a Bot runs with your real browser profile on the
/// gateway host, streamed by the `usual-browser` plugin (`Integrations/hermes-browser`). Watch only.
/// The plugin's status route says whether the Bot has one; its feed is a WebSocket opened with a
/// single-use ticket from `POST /api/auth/ws-ticket`.
@MainActor
@Observable
public final class BotBrowser {
    public enum Connection: Equatable {
        case idle, connecting
        /// Connected, but the Bot's browser isn't open: it opens when the Bot browses.
        case waiting
        case live
        case failed(String)
    }

    /// The tab on show.
    public struct Page: Equatable, Sendable {
        public let url: String?
        public let title: String?

        public init(url: String?, title: String?) {
            self.url = url
            self.title = title
        }
    }

    public let profile: String
    /// The Bot browses with your real profile, headless: there's a browser to watch.
    public private(set) var isAvailable = false
    /// Whether the gateway has the `usual-browser` plugin, once asked: Settings › Plugins tells a
    /// missing plugin from a Bot that doesn't browse with your real profile.
    public private(set) var hasPlugin: Bool?
    public private(set) var connection = Connection.idle
    /// The page as last shown, and its size in pixels.
    public private(set) var frame: CGImage?
    public private(set) var frameSize = CGSize.zero
    public private(set) var page: Page?

    @ObservationIgnored private let auth: @MainActor () -> AuthSession?
    @ObservationIgnored private let picture: @MainActor () -> BrowserPicture
    @ObservationIgnored private let makeSocket: ScreenSocketFactory
    @ObservationIgnored private var socket: (any ScreenSocket)?
    @ObservationIgnored private var stream: Task<Void, Never>?
    @ObservationIgnored private var staleTickets = 0
    @ObservationIgnored var isDemo = false

    nonisolated static let path = "/api/plugins/usual-browser"

    init(
        profile: String, auth: @escaping @MainActor () -> AuthSession?,
        picture: @escaping @MainActor () -> BrowserPicture = { .saved }, makeSocket: @escaping ScreenSocketFactory
    ) {
        self.profile = profile
        self.auth = auth
        self.picture = picture
        self.makeSocket = makeSocket
    }

    // MARK: - Status

    private struct Status: Decodable {
        let available: Bool?
    }

    /// Asks the plugin whether this Bot has a browser to watch. A gateway without the plugin has none.
    public func refresh() async {
        guard !isDemo, let auth = auth() else { return }
        let query = profile.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profile
        do {
            isAvailable = try await auth.json(Status.self, path: "\(Self.path)/status?bot=\(query)").available ?? false
            hasPlugin = true
        } catch GatewayError.http(status: 404, _) {
            isAvailable = false
            hasPlugin = false
        } catch {}
    }

    // MARK: - Watching

    /// Opens the live view. Safe to call again: it starts over.
    public func connect() {
        guard !isDemo else { return }
        stopStream()
        connection = .connecting
        stream = Task { await self.watch() }
    }

    /// Closes the live view.
    public func disconnect() {
        guard !isDemo else { return }
        stopStream()
        connection = .idle
    }

    private func stopStream() {
        stream?.cancel()
        stream = nil
        socket?.close()
        socket = nil
    }

    private func watch() async {
        do {
            guard let auth = auth() else { throw GatewayError.disconnected }
            let ticket = try await auth.webSocketTicket()
            try Task.checkCancellation()
            let url = auth.gateway.browserFeedURL(profile: profile, ticket: ticket, picture: picture())
            let socket = try await makeSocket(url)
            try Task.checkCancellation()
            self.socket = socket
            while !Task.isCancelled {
                let message = try await socket.receive()
                try Task.checkCancellation()
                if Self.isText(message) {
                    staleTickets = 0
                    read(message)
                } else if let image = await Self.decode(message) {
                    try Task.checkCancellation()
                    frame = image
                    frameSize = CGSize(width: image.width, height: image.height)
                    connection = .live
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            ended(by: error)
        }
    }

    /// The feed's text messages are JSON objects; frames are JPEG or PNG, which never start with `{`.
    /// (`ScreenSocket` hands text and binary messages over alike, as bytes.)
    static func isText(_ message: Data) -> Bool { message.first == UInt8(ascii: "{") }

    private struct Message: Decodable {
        let type: String
        let state: String?
        let url: String?
        let title: String?
    }

    private func read(_ message: Data) {
        guard let message = try? JSONDecoder().decode(Message.self, from: message) else { return }
        switch message.type {
        case "state":
            if message.state == "waiting" {
                connection = .waiting
                frame = nil
                frameSize = .zero
                page = nil
            } else if connection != .live {
                connection = .live
            }
        case "tab":
            page = message.url == nil && message.title == nil ? nil : Page(url: message.url, title: message.title)
        default:
            break
        }
    }

    /// Decodes a frame off the main actor: a full page is a few hundred kilobytes of JPEG.
    nonisolated static func decode(_ data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func ended(by error: any Error) {
        socket = nil
        switch (error as? ScreenSocketClosed)?.code {
        case 4401 where staleTickets < 2:
            // The ticket was spent or went stale on the way: one more try with a fresh one.
            staleTickets += 1
            connect()
        case 4401:
            connection = .failed(String(localized: "The gateway refused the browser's connection."))
        case 4404:
            connection = .failed(String(localized: "This Bot isn't on the gateway anymore."))
        default:
            connection =
                error is ScreenSocketClosed
                ? .failed(String(localized: "Lost the connection to the browser."))
                : .failed(AppModel.describe(error))
        }
    }

    #if DEBUG
        /// The demo's browser: a made-up page the agent has open.
        static func demo(profile: String) -> BotBrowser {
            let browser = BotBrowser(
                profile: profile, auth: { nil }, makeSocket: { _ in throw GatewayError.disconnected })
            browser.isDemo = true
            browser.isAvailable = true
            browser.hasPlugin = true
            let page = DemoDesktop.page()
            browser.frame = page.image()
            browser.frameSize = CGSize(width: page.width, height: page.height)
            browser.page = Page(url: "https://flights.example.com/search?to=LIS", title: "Flights to Lisbon")
            browser.connection = .live
            return browser
        }
    #endif
}

/// How a Bot's browser is sent to this device: chosen in Settings, the same for every Bot.
public struct BrowserPicture: Equatable, Sendable {
    public enum Quality: String, CaseIterable, Sendable {
        /// JPEG at 60.
        case dataSaver
        /// JPEG at 90, the plugin's default.
        case standard
        /// PNG: lossless, and several times bigger.
        case best
    }

    public var quality: Quality
    /// 1, or 2 for twice the pixels: sharper on a Retina screen, and about four times the data.
    public var density: Int

    public init(quality: Quality = .standard, density: Int = 1) {
        self.quality = quality
        self.density = density
    }

    /// `UserDefaults` keys, for Settings' `@AppStorage`.
    public static let qualityKey = "browserQuality"
    public static let densityKey = "browserDensity"

    /// As chosen in Settings.
    public static var saved: BrowserPicture {
        let defaults = UserDefaults.standard
        return BrowserPicture(
            quality: defaults.string(forKey: qualityKey).flatMap(Quality.init(rawValue:)) ?? .standard,
            density: defaults.integer(forKey: densityKey) == 2 ? 2 : 1)
    }

    /// The feed's query for this picture; the plugin's defaults are left out.
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        switch quality {
        case .dataSaver: items.append(URLQueryItem(name: "quality", value: "60"))
        case .standard: break
        case .best: items.append(URLQueryItem(name: "format", value: "png"))
        }
        if density == 2 { items.append(URLQueryItem(name: "density", value: "2")) }
        return items
    }
}

extension GatewayAddress {
    /// The browser feed, authenticated by a single-use ticket in the query, like the app's own socket.
    func browserFeedURL(profile: String, ticket: String, picture: BrowserPicture = BrowserPicture()) -> URL {
        var components = URLComponents(url: url("\(BotBrowser.path)/feed"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems =
            [URLQueryItem(name: "bot", value: profile), URLQueryItem(name: "ticket", value: ticket)]
            + picture.queryItems
        return components.url!
    }
}

extension ThreadState {
    /// The running turn is using the agent's browser right now.
    public var isUsingBrowser: Bool {
        guard isRunning, case .activity(let steps) = items.last?.content else { return false }
        return steps.contains { $0.state == .running && $0.name.hasPrefix("browser") }
    }
}
