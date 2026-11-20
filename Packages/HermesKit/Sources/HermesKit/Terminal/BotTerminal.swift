import Foundation
import Observation

/// A shell on the gateway host, as the agent's user, in the agent's working folder: the `usual-bot`
/// plugin's `/terminal` socket, opened with a single-use ticket from `POST /api/auth/ws-ticket`.
/// Only for an agent whose commands run on the host (`terminal.backend: local`); a sandboxed one's
/// shell would be somewhere else than its commands.
///
/// Every message is binary and starts with a tag byte: `0` and bytes (the shell's output; your
/// typing), or `1` and a JSON object (`ready` and `exit` from the plugin; `resize` from here).
@MainActor
@Observable
public final class BotTerminal {
    public enum Availability: Equatable, Sendable {
        case unknown
        case available
        /// The gateway's plugin has no shell: missing, or older than 0.9.0.
        case noPlugin
        /// The agent runs its commands in a sandbox (`docker`, `ssh`, `modal` …), not on the host.
        case sandboxed(backend: String)
    }

    public enum Connection: Equatable, Sendable {
        case idle, connecting, live
        /// The shell exited (`exit`, or the plugin stopped it).
        case ended(code: Int?)
        case failed(String)
    }

    /// Where the shell runs, as the plugin said.
    public struct Place: Equatable, Sendable {
        public let user: String?
        public let host: String?
        public let folder: String?
    }

    public let profile: String
    public private(set) var availability = Availability.unknown
    public private(set) var connection = Connection.idle
    public private(set) var screen = TerminalScreen()
    public private(set) var place: Place?

    @ObservationIgnored private let auth: @MainActor () -> AuthSession?
    @ObservationIgnored private let makeSocket: ScreenSocketFactory
    @ObservationIgnored private var socket: (any ScreenSocket)?
    @ObservationIgnored private var stream: Task<Void, Never>?
    @ObservationIgnored private var outgoing: Task<Void, Never>?
    @ObservationIgnored private var staleTickets = 0
    @ObservationIgnored var isDemo = false
    @ObservationIgnored private var demoLine = ""

    static let output: UInt8 = 0
    static let control: UInt8 = 1

    init(profile: String, auth: @escaping @MainActor () -> AuthSession?, makeSocket: @escaping ScreenSocketFactory) {
        self.profile = profile
        self.auth = auth
        self.makeSocket = makeSocket
    }

    // MARK: - Status

    private struct Status: Decodable {
        let available: Bool?
        let backend: String?
        let user: String?
        let host: String?
        let cwd: String?
    }

    /// Asks the plugin whether this agent has a shell to open.
    public func refresh() async {
        guard !isDemo, let auth = auth() else { return }
        let query = profile.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profile
        do {
            let status = try await auth.json(Status.self, path: "\(UsualPlugin.path)/terminal/status?bot=\(query)")
            if status.available == true {
                availability = .available
            } else {
                availability = .sandboxed(backend: status.backend ?? "sandbox")
            }
            if place == nil { place = Place(user: status.user, host: status.host, folder: status.cwd) }
        } catch GatewayError.http(status: 404, _) {
            availability = .noPlugin
        } catch {}
    }

    // MARK: - The shell

    /// Opens a shell, unless one is open or opening. A new one starts with a clear screen.
    public func start() {
        guard !isDemo else { return }
        switch connection {
        case .connecting, .live: return
        case .idle, .ended, .failed: break
        }
        open()
    }

    private func open() {
        stopStream()
        screen = TerminalScreen(columns: screen.columns, rows: screen.rows)
        connection = .connecting
        stream = Task { await self.run() }
    }

    /// Closes the shell; the plugin stops what runs in it.
    public func stop() {
        guard !isDemo else { return }
        stopStream()
        connection = .idle
    }

    private func stopStream() {
        stream?.cancel()
        stream = nil
        outgoing?.cancel()
        outgoing = nil
        socket?.close()
        socket = nil
    }

    /// What you typed, as the bytes a terminal sends (`TerminalKeys`).
    public func send(_ text: String) {
        if isDemo { return demoType(text) }
        guard case .live = connection else { return }
        write([Self.output] + Array(text.utf8))
    }

    /// Pasted text, marked as pasted when the shell asked, so it isn't run line by line.
    public func paste(_ text: String) {
        let text = text.replacing("\r\n", with: "\r").replacing("\n", with: "\r")
        send(screen.bracketedPaste ? "\u{1B}[200~\(text)\u{1B}[201~" : text)
    }

    /// The drawer's size in characters. The shell is told, so it wraps where the drawer does.
    public func resize(columns: Int, rows: Int) {
        guard columns != screen.columns || rows != screen.rows else { return }
        screen.resize(columns: columns, rows: rows)
        guard case .live = connection else { return }
        sendSize()
    }

    private func sendSize() {
        let size: JSONValue = [
            "type": "resize", "cols": .number(Double(screen.columns)), "rows": .number(Double(screen.rows)),
        ]
        if let json = try? JSONEncoder().encode(size) { write([Self.control] + Array(json)) }
    }

    /// Sends in order: each write waits for the one before.
    private func write(_ bytes: [UInt8]) {
        guard let socket else { return }
        let previous = outgoing
        let data = Data(bytes)
        outgoing = Task {
            await previous?.value
            try? await socket.send(data)
        }
    }

    private func run() async {
        do {
            guard let auth = auth() else { throw GatewayError.disconnected }
            let ticket = try await auth.webSocketTicket()
            try Task.checkCancellation()
            let url = auth.gateway.terminalURL(
                profile: profile, ticket: ticket, columns: screen.columns, rows: screen.rows)
            let socket = try await makeSocket(url)
            try Task.checkCancellation()
            self.socket = socket
            while !Task.isCancelled {
                let message = try await socket.receive()
                try Task.checkCancellation()
                read(message)
            }
        } catch {
            guard !Task.isCancelled else { return }
            ended(by: error)
        }
    }

    private struct Message: Decodable {
        let type: String
        let code: Int?
        let user: String?
        let host: String?
        let cwd: String?
    }

    func read(_ message: Data) {
        guard let tag = message.first else { return }
        let body = message.dropFirst()
        if tag == Self.output {
            screen.feed(Data(body))
            answerScreen()
            if connection == .connecting { connection = .live }
            return
        }
        guard let message = try? JSONDecoder().decode(Message.self, from: Data(body)) else { return }
        switch message.type {
        case "ready":
            staleTickets = 0
            connection = .live
            place = Place(user: message.user, host: message.host, folder: message.cwd)
            sendSize()
        case "exit":
            connection = .ended(code: message.code)
            stopStream()
        default:
            break
        }
    }

    /// Replies the shell asked the screen for, such as where the cursor is.
    private func answerScreen() {
        guard !screen.replies.isEmpty else { return }
        for reply in screen.replies { write([Self.output] + Array(reply)) }
        screen.replies = []
    }

    private func ended(by error: any Error) {
        socket = nil
        switch (error as? ScreenSocketClosed)?.code {
        case 4401 where staleTickets < 2:
            // The ticket was spent or went stale on the way: one more try with a fresh one.
            staleTickets += 1
            open()
        case 4401:
            connection = .failed(String(localized: "The gateway refused the shell's connection."))
        case 4404:
            connection = .failed(String(localized: "This Bot isn't on the gateway anymore."))
        case 4409:
            connection = .failed(
                String(localized: "This Bot runs its commands in a sandbox, so there's no shell to open."))
        default:
            connection =
                error is ScreenSocketClosed
                ? .failed(String(localized: "Lost the connection to the shell. What ran in it was stopped."))
                : .failed(AppModel.describe(error))
        }
    }

    // MARK: - Demo

    #if DEBUG
        static let demoPrompt = "\u{1B}[32matlas\u{1B}[0m \u{1B}[34m~/work\u{1B}[0m $ "

        /// The demo's shell: a made-up session, and nothing you type runs.
        static func demo(profile: String) -> BotTerminal {
            let terminal = BotTerminal(
                profile: profile, auth: { nil }, makeSocket: { _ in throw GatewayError.disconnected })
            terminal.isDemo = true
            terminal.availability = .available
            terminal.connection = .live
            terminal.place = Place(user: profile, host: "hermes.example.com", folder: "~/work")
            terminal.screen.feed(
                demoPrompt + "ls docs/search\r\n"
                    + "index-nightly.sh  \u{1B}[33mturbopuffer-trial.md\u{1B}[0m  fallback.md\r\n"
                    + demoPrompt + "git log --oneline -2\r\n"
                    + "\u{1B}[33ma91c2e0\u{1B}[0m Add Turbopuffer trial plan\r\n"
                    + "\u{1B}[33m7f03b1d\u{1B}[0m Keep current search as fallback\r\n" + demoPrompt)
            return terminal
        }
    #endif

    /// Echoes what you type, and answers every line with what the demo is.
    private func demoType(_ text: String) {
        #if DEBUG
            for character in text {
                switch character {
                case "\r":
                    let line = demoLine.trimmingCharacters(in: .whitespaces)
                    demoLine = ""
                    let answer =
                        line.isEmpty
                        ? "" : "This is the demo, so nothing runs. Sign in to your gateway to use a real shell.\r\n"
                    screen.feed("\r\n" + answer + Self.demoPrompt)
                case "\u{7F}":
                    guard !demoLine.isEmpty else { continue }
                    demoLine.removeLast()
                    screen.feed("\u{8} \u{8}")
                case "\u{3}":
                    demoLine = ""
                    screen.feed("^C\r\n" + Self.demoPrompt)
                default:
                    guard character.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
                        continue
                    }
                    demoLine.append(character)
                    screen.feed(String(character))
                }
            }
        #endif
    }
}

extension GatewayAddress {
    /// The shell's socket, authenticated by a single-use ticket in the query, like the app's own socket.
    func terminalURL(profile: String, ticket: String, columns: Int, rows: Int) -> URL {
        var components = URLComponents(url: url("\(UsualPlugin.path)/terminal"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [
            URLQueryItem(name: "bot", value: profile), URLQueryItem(name: "ticket", value: ticket),
            URLQueryItem(name: "cols", value: "\(columns)"), URLQueryItem(name: "rows", value: "\(rows)"),
        ]
        return components.url!
    }
}
