import Foundation
import Network
import Synchronization

/// A one-shot HTTP listener on `127.0.0.1` that catches the browser redirect finishing sign-in
/// (`GET /callback?code=…&state=…`), answers with a short "you can close this" page, and hands
/// the query to the waiting caller. The gateway only accepts loopback IP redirects (RFC 8252 §7.3).
final class LoopbackReceiver: @unchecked Sendable {
    // @unchecked: NWListener and NWConnection are driven from `queue`; mutable state is in `state`.

    static let callbackPath = "/callback"

    let port: UInt16
    var redirectURI: String { "http://127.0.0.1:\(port)\(Self.callbackPath)" }

    private let listener: NWListener
    private let queue: DispatchQueue
    private let state = Mutex(State())

    private struct State {
        var waiter: CheckedContinuation<[URLQueryItem], any Error>?
        var outcome: Result<[URLQueryItem], any Error>?
    }

    private init(listener: NWListener, queue: DispatchQueue, port: UInt16) {
        self.listener = listener
        self.queue = queue
        self.port = port
    }

    /// Starts listening on an ephemeral loopback port.
    static func start() async throws -> LoopbackReceiver {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "UsualBot.LoopbackReceiver")
        let ready = Mutex<CheckedContinuation<UInt16, any Error>?>(nil)

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            ready.withLock { $0 = continuation }
            listener.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    let port = listener.port?.rawValue ?? 0
                    ready.withLock { $0.take() }?.resume(returning: port)
                case .failed(let error):
                    ready.withLock { $0.take() }?.resume(
                        throwing: GatewayError.signInFailed(error.localizedDescription))
                case .cancelled:
                    ready.withLock { $0.take() }?.resume(throwing: GatewayError.cancelled)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { connection in connection.cancel() }
            listener.start(queue: queue)
        }

        let receiver = LoopbackReceiver(listener: listener, queue: queue, port: port)
        listener.newConnectionHandler = { [weak receiver] connection in receiver?.handle(connection) }
        return receiver
    }

    /// Waits for the redirect. Throws `.timedOut` after `timeout`, `.cancelled` after `cancel()`.
    func waitForCallback(timeout: Duration) async throws -> [URLQueryItem] {
        queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in
            self?.finish(.failure(GatewayError.timedOut))
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let ready = state.withLock { state -> Result<[URLQueryItem], any Error>? in
                    if let outcome = state.outcome { return outcome }
                    state.waiter = continuation
                    return nil
                }
                if let ready { continuation.resume(with: ready) }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        finish(.failure(GatewayError.cancelled))
    }

    func stop() {
        listener.cancel()
    }

    private func finish(_ outcome: Result<[URLQueryItem], any Error>) {
        let waiter = state.withLock { state -> CheckedContinuation<[URLQueryItem], any Error>? in
            guard state.outcome == nil else { return nil }
            state.outcome = outcome
            return state.waiter.take()
        }
        waiter?.resume(with: outcome)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, _, _ in
            guard let self else { return connection.cancel() }
            let target = data.flatMap { Self.requestTarget(in: $0) }
            if let target, target.path == Self.callbackPath {
                Self.respond(on: connection, status: "200 OK", body: Self.successPage)
                finish(.success(target.queryItems ?? []))
            } else {
                Self.respond(on: connection, status: "404 Not Found", body: "")
            }
        }
    }

    /// Parses the request line of an HTTP/1.x GET, e.g. `GET /callback?code=x HTTP/1.1`.
    static func requestTarget(in data: Data) -> URLComponents? {
        guard let text = String(data: data, encoding: .utf8),
            let line = text.split(separator: "\r\n", maxSplits: 1).first
        else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/") else { return nil }
        return URLComponents(string: "http://127.0.0.1" + parts[1])
    }

    private static func respond(on connection: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let head =
            "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(bodyData.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(head.utf8) + bodyData,
            completion: .contentProcessed { _ in connection.cancel() })
    }

    static let successPage = """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Signed in to Usual Bot</title>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#F6F6F7;color:#18181B;
        font:16px -apple-system,system-ui,sans-serif}@media(prefers-color-scheme:dark){body{background:#161618;
        color:#F2F2F3}}</style></head><body><main><h1 style="font-size:20px;font-weight:600">You're signed in</h1>
        <p>You can close this tab and go back to Usual Bot.</p></main></body></html>
        """
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

extension Optional {
    /// Returns the wrapped value and leaves `nil` behind.
    fileprivate mutating func take() -> Wrapped? {
        defer { self = nil }
        return self
    }
}
