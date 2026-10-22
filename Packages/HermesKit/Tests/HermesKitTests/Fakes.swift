import Foundation
import Synchronization

@testable import HermesKit

/// An HTTP transport that answers from a closure and records every request.
final class ScriptedHTTP: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, String)

    private let handler: Handler
    private let log = Mutex<[URLRequest]>([])

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] { log.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        let (status, body) = try await handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

final class MemoryTokenStore: TokenStore {
    private let items = Mutex<[URL: TokenSet]>([:])

    func load(for gateway: GatewayAddress) throws -> TokenSet? { items.withLock { $0[gateway.baseURL] } }
    func save(_ tokens: TokenSet, for gateway: GatewayAddress) throws {
        items.withLock { $0[gateway.baseURL] = tokens }
    }
    func delete(for gateway: GatewayAddress) throws { _ = items.withLock { $0.removeValue(forKey: gateway.baseURL) } }
}

/// One end of a WebSocket that a test drives: `deliver` pushes frames to the client,
/// `sent` shows what the client wrote.
final class FakeSocket: WebSocketConnection {
    private struct Inbox {
        var queue: [String] = []
        var waiter: CheckedContinuation<String?, Never>?
        var closed = false
    }

    private let inbox = Mutex(Inbox())
    private let outbound = Mutex<[String]>([])

    var sent: [JSONValue] {
        outbound.withLock { $0 }.compactMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    }

    func deliver(_ text: String) {
        let waiter = inbox.withLock { inbox -> CheckedContinuation<String?, Never>? in
            if let waiter = inbox.waiter.take() { return waiter }
            inbox.queue.append(text)
            return nil
        }
        waiter?.resume(returning: text)
    }

    func send(_ text: String) async throws { outbound.withLock { $0.append(text) } }

    func receive() async throws -> String {
        let text: String? = await withCheckedContinuation { continuation in
            let immediate = inbox.withLock { inbox -> String?? in
                if !inbox.queue.isEmpty { return .some(inbox.queue.removeFirst()) }
                if inbox.closed { return .some(nil) }
                inbox.waiter = continuation
                return nil
            }
            if let immediate { continuation.resume(returning: immediate) }
        }
        guard let text else { throw GatewayError.disconnected }
        return text
    }

    func close() {
        let waiter = inbox.withLock { inbox in
            inbox.closed = true
            return inbox.waiter.take()
        }
        waiter?.resume(returning: nil)
    }
}

extension Optional {
    fileprivate mutating func take() -> Wrapped? {
        defer { self = nil }
        return self
    }
}

extension URLRequest {
    var jsonBody: JSONValue? {
        httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }
}

let testGateway = try! GatewayAddress(parsing: "http://100.101.102.103:9119")

func tokenJSON(access: String, refresh: String, expiresAt: Double) -> String {
    """
    {"access_token":"\(access)","refresh_token":"\(refresh)","token_type":"Bearer",\
    "expires_at":\(expiresAt),"provider":"nous","user_id":"u1"}
    """
}
