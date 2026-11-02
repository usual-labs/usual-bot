#if canImport(TailscaleKit)
    import Foundation
    import TailscaleKit

    /// The app's own device on your tailnet: a userspace Tailscale node running inside the app, so
    /// a tailnet gateway is reachable while the Tailscale VPN is off. Requests go through the node's
    /// SOCKS5 proxy on a loopback port; nothing else on the device uses it.
    public actor Tailnet {
        public enum State: Sendable, Equatable {
            /// Not running: not started yet, stopped, or paused while the app is in the background.
            case stopped
            case starting
            /// The device isn't in a tailnet yet: someone has to sign in to Tailscale at this page.
            case needsLogin(URL)
            case running(Device)
            case failed(String)
        }

        /// This device as the tailnet knows it.
        public struct Device: Sendable, Equatable {
            /// Its machine name, e.g. `usual-bot-iphone`.
            public let name: String
            /// Its Tailscale IPv4 address, e.g. `100.101.102.103`.
            public let address: String?
        }

        /// Each change of state. Has one listener.
        public nonisolated let states: AsyncStream<State>
        private let continuation: AsyncStream<State>.Continuation
        private let configuration: Configuration
        /// The node's messages, Swift and Go alike, when a log file was given.
        private let logFile: Int32?
        private var node: TailscaleNode?
        private var state = State.stopped
        /// The node coming up, then its proxied session. Cleared when it fails or stops.
        private var ready: Task<URLSession, any Error>?
        /// A stopped node shutting down, which the next one waits for: both use the same files.
        private var closing: Task<Void, Never>?

        /// `directory` keeps the node's keys between launches and stays out of backups, so a
        /// restored backup doesn't clone this device. `hostName` is its name in the tailnet.
        public init(directory: URL, hostName: String, logFile: URL? = nil) {
            var directory = directory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            configuration = Configuration(
                hostName: hostName, path: directory.path(percentEncoded: false), authKey: nil,
                controlURL: kDefaultControlURL, ephemeral: false)
            self.logFile = logFile.map { open($0.path(percentEncoded: false), O_WRONLY | O_CREAT | O_TRUNC, 0o600) }
                .flatMap { $0 >= 0 ? $0 : nil }
            (states, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        }

        /// A session whose requests go through the node. Starts the node on first use and waits
        /// until it runs, which includes waiting for the first Tailscale sign-in.
        public func session() async throws -> URLSession {
            let task: Task<URLSession, any Error>
            if let ready {
                task = ready
            } else {
                task = Task { try await bringUp() }
                ready = task
            }
            do {
                return try await task.value
            } catch {
                if ready == task { ready = nil }
                throw error
            }
        }

        /// Stops the node until the next `session()`, which starts it again with the keys it has.
        public func stop() {
            guard let node else { return }
            ready = nil
            self.node = nil
            publish(.stopped)
            closing = Task { try? await node.close() }
        }

        /// Stops a running node for the background. iOS cuts a suspended app's sockets and the node
        /// doesn't recover from that (its UDP receivers and link monitor stay dead). A node waiting
        /// for its first sign-in keeps waiting: people often finish that in another app.
        public func suspend() {
            guard case .running = state else { return }
            log("Stopping for the background")
            stop()
        }

        /// Signs this device out of its tailnet, which removes it there, and stops it. The next
        /// `session()` asks for a Tailscale sign-in again.
        public func signOut() async throws {
            guard case .running = state, let node else { return }
            // The proxy's port also serves LocalAPI to requests with this header and its key.
            // TailscaleKit's own logout call isn't public.
            let loopback = try await node.loopback()
            var request = URLRequest(url: URL(string: "http://\(loopback.address)/localapi/v0/logout")!)
            request.httpMethod = "POST"
            request.setValue("localapi", forHTTPHeaderField: "Sec-Tailscale")
            let credential = Data("tsnet:\(loopback.localAPIKey)".utf8).base64EncodedString()
            request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                throw URLError(.badServerResponse)
            }
            log("Signed out of Tailscale")
            stop()
        }

        private func bringUp() async throws -> URLSession {
            await closing?.value
            closing = nil
            publish(.starting)
            // Go wraps the descriptor in a file it may close, so each node gets its own copy.
            let sink = Sink(logFileHandle: logFile.map { dup($0) } ?? -1, file: logFile)
            let node: TailscaleNode
            do {
                node = try self.node ?? TailscaleNode(config: configuration, logger: sink)
            } catch {
                publish(.failed(String(describing: error)))
                throw error
            }
            self.node = node
            do {
                let login = Task { await watchForLogin(node) }
                defer { login.cancel() }
                try await node.up()
                let (proxied, _) = try await URLSessionConfiguration.tailscaleSession(node)
                let me = await Status.read(node)?.me
                // Stopped while it came up: its proxy is gone.
                guard self.node === node else { throw CancellationError() }
                publish(.running(Device(name: me?.name ?? configuration.hostName, address: me?.ipv4)))
                return URLSession(configuration: proxied)
            } catch {
                if self.node === node { publish(.failed(String(describing: error))) }
                throw error
            }
        }

        /// While the node comes up, checks its status every second for the sign-in page Tailscale
        /// hands out to a new device.
        private func watchForLogin(_ node: TailscaleNode) async {
            while !Task.isCancelled {
                if let status = await Status.read(node), status.backendState == "NeedsLogin",
                    let page = status.authURL.flatMap(URL.init(string:))
                {
                    publish(.needsLogin(page))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }

        private func publish(_ new: State) {
            guard new != state else { return }
            state = new
            switch new {
            case .stopped: log("Stopped")
            case .starting: log("Starting")
            case .needsLogin: log("Waiting for Tailscale sign-in")
            case .running: log("Running")
            case .failed(let reason): log("Failed: \(reason)")
            }
            continuation.yield(new)
        }

        private func log(_ message: String) {
            Sink(logFileHandle: nil, file: logFile).log("tailnet: \(message)")
        }
    }

    /// The parts of the node's status (Tailscale's `ipnstate.Status`) the app reads.
    private struct Status: Decodable {
        struct Node: Decodable {
            let hostName: String
            let dnsName: String?
            let tailscaleIPs: [String]?

            /// The name the tailnet gave it: the first label of its MagicDNS name, which carries a
            /// suffix when another device already had the host name.
            var name: String { dnsName?.split(separator: ".").first.map(String.init) ?? hostName }
            var ipv4: String? { tailscaleIPs?.first { !$0.contains(":") } }

            enum CodingKeys: String, CodingKey {
                case hostName = "HostName"
                case dnsName = "DNSName"
                case tailscaleIPs = "TailscaleIPs"
            }
        }

        let backendState: String
        let authURL: String?
        let me: Node?

        enum CodingKeys: String, CodingKey {
            case backendState = "BackendState"
            case authURL = "AuthURL"
            case me = "Self"
        }

        static func read(_ node: TailscaleNode) async -> Status? {
            guard let data = try? await node.statusJSON() else { return nil }
            return try? JSONDecoder().decode(Status.self, from: data)
        }
    }

    /// Hands Go a descriptor for its log and writes the Swift side's messages to the same file.
    private struct Sink: LogSink {
        let logFileHandle: Int32?
        let file: Int32?

        func log(_ message: String) {
            guard let file else { return }
            let line = "\(Date.now.ISO8601Format()) \(message)\n"
            _ = line.withCString { write(file, $0, strlen($0)) }
        }
    }
#endif
