import Foundation

/// Files an agent named in a chat (an image it made, a screenshot, a page you sent), read from
/// the gateway on demand. The latest few stay in memory, and a file asked for by several views at
/// once is fetched once.
@MainActor
public final class MediaStore {
    private let auth: @MainActor () -> AuthSession?
    private var cache: [String: Data] = [:]
    /// Cache keys, oldest first.
    private var order: [String] = []
    private var loading: [String: Task<Data, any Error>] = [:]

    /// Enough for a chat screen of images without holding a whole history of them.
    private static let cacheLimit = 40

    init(auth: @escaping @MainActor () -> AuthSession?) {
        self.auth = auth
    }

    /// The file at `path` on the gateway, as `profile` sees it: absolute, or relative to that
    /// profile's workspace. The gateway reads up to 16 MB.
    public func file(at path: String, profile: String) async throws -> Data {
        let key = profile + "\u{0}" + path
        if let data = cache[key] { return data }
        #if DEBUG
            if let data = demoFiles[path] { return data }
        #endif
        if let task = loading[key] { return try await task.value }
        guard let auth = auth() else { throw GatewayError.disconnected }
        let task = Task { try await Self.fetch(path, profile: profile, auth: auth) }
        loading[key] = task
        defer { loading[key] = nil }
        let data = try await task.value
        remember(data, for: key)
        return data
    }

    func clear() {
        cache = [:]
        order = []
    }

    private func remember(_ data: Data, for key: String) {
        cache[key] = data
        order.append(key)
        while order.count > Self.cacheLimit { cache[order.removeFirst()] = nil }
    }

    /// `GET /api/fs/read-data-url`: what the official app reads remote media with. (`/api/media`
    /// only serves the default profile's image folders.)
    private static func fetch(_ path: String, profile: String, auth: AuthSession) async throws -> Data {
        struct Reply: Decodable { let dataUrl: String }
        let reply = try await auth.json(
            Reply.self, path: "/api/fs/read-data-url?path=\(escape(path))&profile=\(escape(profile))")
        guard let data = decode(dataURL: reply.dataUrl) else { throw GatewayError.invalidResponse }
        return data
    }

    /// The bytes of a `data:<type>;base64,<payload>` URL.
    static func decode(dataURL: String) -> Data? {
        guard dataURL.hasPrefix("data:"), let comma = dataURL.firstIndex(of: ","),
            dataURL[..<comma].hasSuffix(";base64")
        else { return nil }
        return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    }

    private static func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? component
    }

    #if DEBUG
        /// The demo's files, by path; it has no gateway to read from.
        var demoFiles: [String: Data] = [:]
    #endif
}
