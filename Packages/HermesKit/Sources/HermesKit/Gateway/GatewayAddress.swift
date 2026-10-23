import Foundation

/// Where a Hermes gateway's dashboard listener lives, e.g. `https://hermes.example.com` or
/// `http://100.101.102.103:9119`. A path prefix (for gateways behind a reverse proxy) is kept.
public struct GatewayAddress: Hashable, Sendable, Codable {
    /// Scheme, host, optional port and optional path prefix, with no trailing slash.
    public let baseURL: URL

    public enum ParseError: Error, Equatable {
        case empty
        case invalid
        /// Plain `http` to a host on the public internet would send sign-in tokens unencrypted.
        case insecureHTTP(host: String)
    }

    /// Accepts what a person would paste: with or without a scheme, with or without a trailing slash.
    /// Without a scheme, private and Tailscale addresses get `http`, everything else `https`.
    public init(parsing input: String) throws(ParseError) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        let hasScheme = trimmed.contains("://")
        guard var components = URLComponents(string: hasScheme ? trimmed : "http://" + trimmed),
            let host = components.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil
        else { throw .invalid }

        let isPrivate = Self.isPrivate(host: host)
        if !hasScheme {
            components.scheme = isPrivate ? "http" : "https"
        }
        switch components.scheme?.lowercased() {
        case "https": break
        case "http" where isPrivate: break
        case "http": throw .insecureHTTP(host: host)
        default: throw .invalid
        }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let url = components.url else { throw .invalid }
        baseURL = url
    }

    /// A gateway endpoint, e.g. `url("/api/status")`.
    public func url(_ path: String) -> URL {
        URL(string: baseURL.absoluteString + path)!
    }

    /// The JSON-RPC socket, authenticated by a single-use ticket in the query.
    /// Remote gateways refuse tickets carried in the `Sec-WebSocket-Protocol` header.
    func webSocketURL(ticket: String) -> URL {
        var components = URLComponents(url: url("/api/ws"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        return components.url!
    }

    /// Short form for the UI: host and port.
    public var displayName: String {
        guard let host = baseURL.host(percentEncoded: false) else { return baseURL.absoluteString }
        return baseURL.port.map { "\(host):\($0)" } ?? host
    }

    /// A Tailscale address (100.64.0.0/10, fd7a:115c:a1e0::/48) or MagicDNS name (`*.ts.net`),
    /// which a device reaches only while Tailscale is on and signed in to the same tailnet.
    var isTailnet: Bool {
        guard let host = baseURL.host(percentEncoded: false)?.lowercased() else { return false }
        if host.hasSuffix(".ts.net") || host.hasPrefix("fd7a:115c:a1e0:") { return true }
        guard let octets = Self.ipv4Octets(host) else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    /// Loopback, private-network, link-local and Tailscale (100.64.0.0/10, fd7a::/16) addresses,
    /// plus `.local` and single-label names. Traffic to these never crosses the open internet
    /// unencrypted on its own, so plain `http` is allowed. App Transport Security agrees.
    static func isPrivate(host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if let octets = ipv4Octets(host) {
            switch (octets[0], octets[1]) {
            case (127, _), (10, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            case (100, 64...127): return true
            default: return false
            }
        }
        if host.contains(":") {
            return host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe8")
                || host.hasPrefix("fe9") || host.hasPrefix("fea") || host.hasPrefix("feb")
        }
        return !host.contains(".")
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }.filter { (0...255).contains($0) }
        return octets.count == 4 ? octets : nil
    }
}
