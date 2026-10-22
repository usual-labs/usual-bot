import Foundation

/// A text WebSocket. `URLSessionWebSocketTask` in the app; an in-memory pair in tests.
public protocol WebSocketConnection: Sendable {
    func send(_ text: String) async throws
    /// The next text frame. Throws once the socket is closed.
    func receive() async throws -> String
    func close()
}

final class URLSessionWebSocket: WebSocketConnection, @unchecked Sendable {
    // @unchecked: URLSessionWebSocketTask is safe to use from any thread.
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession = .shared) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: throw GatewayError.invalidResponse
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
