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

    /// Audio and video downloaded for playing, by cache key, oldest first.
    private var playable: [(key: String, url: URL)] = []
    private var downloading: [String: Task<URL, any Error>] = [:]
    /// This run's own folder for them. Files from runs that have ended are deleted at launch.
    private let playbackFolder: URL

    /// A few voice memos and clips; each is a whole file on disk.
    private static let playableLimit = 8

    init(
        auth: @escaping @MainActor () -> AuthSession?, temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.auth = auth
        let pid = ProcessInfo.processInfo.processIdentifier
        playbackFolder = temporaryDirectory.appending(path: "\(Self.playbackPrefix)\(pid)", directoryHint: .isDirectory)
        Self.removeEndedRuns(in: temporaryDirectory)
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

    /// A local copy of the audio or video file at `path`, to play. `AVPlayer` can't send the
    /// sign-in with its requests, so the whole file is downloaded first, through
    /// `GET /api/fs/download` (as `profile` sees it, with no size cap, unlike `file(at:profile:)`).
    /// The copy keeps the file's name, so players and Share see its type. Copies last until
    /// sign-out or the app quits; the next launch deletes them.
    public func playableFile(at path: String, profile: String) async throws -> URL {
        let key = profile + "\u{0}" + path
        if let index = playable.firstIndex(where: { $0.key == key }) {
            let url = playable[index].url
            if FileManager.default.fileExists(atPath: url.path) { return url }
            playable.remove(at: index)
        }
        if let task = downloading[key] { return try await task.value }
        let name = (path as NSString).lastPathComponent
        let folder = playbackFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let task: Task<URL, any Error>
        #if DEBUG
            let demo = demoFiles[path]
            let maker = demoMakers[path]
        #else
            let demo: Data? = nil
            let maker: (@Sendable () async -> Data?)? = nil
        #endif
        if let demo {
            task = Task.detached { try Self.write(demo, named: name, in: folder) }
        } else if let maker {
            task = Task.detached {
                guard let data = await maker() else { throw GatewayError.invalidResponse }
                return try Self.write(data, named: name, in: folder)
            }
        } else {
            guard let auth = auth() else { throw GatewayError.disconnected }
            let query = "path=\(Self.escape(path))&profile=\(Self.escape(profile))"
            task = Task.detached {
                let data = try await auth.download(path: "/api/fs/download?\(query)")
                return try Self.write(data, named: name, in: folder)
            }
        }
        downloading[key] = task
        defer { downloading[key] = nil }
        let url = try await task.value
        playable.append((key, url))
        while playable.count > Self.playableLimit {
            try? FileManager.default.removeItem(at: playable.removeFirst().url.deletingLastPathComponent())
        }
        return url
    }

    func clear() {
        cache = [:]
        order = []
        playable = []
        try? FileManager.default.removeItem(at: playbackFolder)
    }

    nonisolated private static let playbackPrefix = "UsualBot-playback-"

    nonisolated private static func write(_ data: Data, named name: String, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name.isEmpty ? "media" : name)
        try data.write(to: url)
        return url
    }

    /// Deletes the playback folders of runs that have ended. Each run has its own, named by its
    /// process, because a Mac's temporary folder is shared by every copy of the app running.
    private static func removeEndedRuns(in directory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(playbackPrefix) {
            guard let pid = Int32(name.dropFirst(playbackPrefix.count)) else { continue }
            let running = kill(pid, 0) == 0 || errno == EPERM
            if !running || pid == ProcessInfo.processInfo.processIdentifier {
                try? FileManager.default.removeItem(at: directory.appending(path: name))
            }
        }
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
        /// Demo files made when first asked for, such as a voice memo spoken on this device.
        var demoMakers: [String: @Sendable () async -> Data?] = [:]
    #endif
}
