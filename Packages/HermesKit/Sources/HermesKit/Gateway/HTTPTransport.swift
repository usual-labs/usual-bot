import Foundation

/// Sends one HTTP request. `URLSession` in the app; a scripted fake in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        return (data, http)
    }
}

extension HTTPTransport {
    /// Sends `request` and decodes a 2xx JSON body. Network failures become `.unreachable`,
    /// other statuses `.http` with the gateway's `detail` or `error` message when it gives one.
    func json<T: Decodable & Sendable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await send(request)
        } catch let error as GatewayError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw GatewayError.cancelled
        } catch {
            throw GatewayError.unreachable(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GatewayError.http(status: response.statusCode, message: Self.message(in: data))
        }
        do {
            return try JSONDecoder.gateway.decode(T.self, from: data)
        } catch {
            throw GatewayError.invalidResponse
        }
    }

    /// FastAPI errors carry `{"detail": "..."}`; the auth routes use `{"error": "..."}`.
    static func message(in data: Data) -> String? {
        guard let body = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        return body["detail"]?.stringValue ?? body["error"]?.stringValue
    }
}

extension URLRequest {
    static func json(_ url: URL, method: String = "GET", body: (any Encodable)? = nil, bearer: String? = nil)
        -> URLRequest
    {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder.gateway.encode(body)
        }
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

extension JSONDecoder {
    /// The gateway speaks snake_case JSON.
    static var gateway: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

extension JSONEncoder {
    static var gateway: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}
