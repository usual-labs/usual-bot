import CryptoKit
import Foundation

/// The roster and recent messages from the last connection, so the app shows your chats straight
/// away on launch and while offline. Lives in the Caches directory (the system may purge it) and is
/// deleted on sign-out.
struct OfflineCache: Sendable {
    struct Snapshot: Codable, Equatable, Sendable {
        var contacts: [Contact]
        var threads: [Contact.ID: CachedThread]
        /// Agents' own pictures. Optional, so a cache written before pictures still loads.
        var pictures: [Contact.ID: BotPictures.Stored]? = nil
    }

    let directory: URL

    init(directory: URL = URL.cachesDirectory.appending(path: "UsualBot", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func load(for gateway: GatewayAddress) -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: gateway)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot, for gateway: GatewayAddress) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(
            to: fileURL(for: gateway), options: [.atomic, .completeFileProtection])
    }

    func delete(for gateway: GatewayAddress) {
        try? FileManager.default.removeItem(at: fileURL(for: gateway))
    }

    /// One file per gateway, named by a hash so the address isn't spelled out on disk.
    private func fileURL(for gateway: GatewayAddress) -> URL {
        let digest = SHA256.hash(data: Data(gateway.baseURL.absoluteString.utf8))
        let name = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(name).json")
    }
}
