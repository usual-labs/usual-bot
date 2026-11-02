import Foundation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
struct MediaStoreTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

    private func store(_ http: ScriptedHTTP, temporaryDirectory: URL = FileManager.default.temporaryDirectory)
        -> MediaStore
    {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        return MediaStore(auth: { auth }, temporaryDirectory: temporaryDirectory)
    }

    @Test func readsTheFileAsTheAgentsProfileAndCachesIt() async throws {
        let png = png
        let http = ScriptedHTTP { _ in (200, #"{"dataUrl":"data:image/png;base64,\#(png.base64EncodedString())"}"#) }
        let media = store(http)

        #expect(try await media.file(at: "/home/h/.hermes/profiles/ops/cache/chart 1.png", profile: "ops") == png)
        #expect(try await media.file(at: "/home/h/.hermes/profiles/ops/cache/chart 1.png", profile: "ops") == png)

        #expect(http.requests.count == 1)
        let request = try #require(http.requests.first)
        #expect(request.url?.path == "/api/fs/read-data-url")
        #expect(
            request.url?.query
                == "path=%2Fhome%2Fh%2F.hermes%2Fprofiles%2Fops%2Fcache%2Fchart%201.png&profile=ops")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer a0")
    }

    @Test func viewsAskingAtOnceShareOneRequest() async throws {
        let png = png
        let started = Mutex(0)
        let http = ScriptedHTTP { _ in
            started.withLock { $0 += 1 }
            // sleep-ok: a slow server, so both calls overlap
            try await Task.sleep(for: .milliseconds(50))
            return (200, #"{"dataUrl":"data:image/png;base64,\#(png.base64EncodedString())"}"#)
        }
        let media = store(http)
        async let first = media.file(at: "/a.png", profile: "ops")
        async let second = media.file(at: "/a.png", profile: "ops")
        #expect(try await [first, second] == [png, png])
        #expect(started.withLock { $0 } == 1)
    }

    @Test func refusedFilesSurfaceTheGatewaysReason() async throws {
        let http = ScriptedHTTP { _ in (404, #"{"detail":"File not found"}"#) }
        await #expect(throws: GatewayError.http(status: 404, message: "File not found")) {
            try await store(http).file(at: "/gone.png", profile: "ops")
        }
    }

    @Test func downloadsAudioWholeToAFileNamedLikeIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MediaStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let http = ScriptedHTTP { _ in (200, "ID3 audio bytes") }
        let media = store(http, temporaryDirectory: folder)

        let url = try await media.playableFile(at: "/home/h/.hermes/cache/audio/tts_1.mp3", profile: "ops")
        #expect(try await media.playableFile(at: "/home/h/.hermes/cache/audio/tts_1.mp3", profile: "ops") == url)

        #expect(url.lastPathComponent == "tts_1.mp3")
        #expect(try Data(contentsOf: url) == Data("ID3 audio bytes".utf8))
        #expect(http.requests.count == 1)
        let request = try #require(http.requests.first)
        #expect(request.url?.path == "/api/fs/download")
        #expect(request.url?.query == "path=%2Fhome%2Fh%2F.hermes%2Fcache%2Faudio%2Ftts_1.mp3&profile=ops")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer a0")

        // Signing out deletes the copies.
        media.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aDeletedCopyIsDownloadedAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MediaStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let http = ScriptedHTTP { _ in (200, "clip") }
        let media = store(http, temporaryDirectory: folder)
        let url = try await media.playableFile(at: "/clip.mp4", profile: "ops")
        try FileManager.default.removeItem(at: url)

        let again = try await media.playableFile(at: "/clip.mp4", profile: "ops")
        #expect(FileManager.default.fileExists(atPath: again.path))
        #expect(http.requests.count == 2)
    }

    @Test func launchDeletesCopiesFromRunsThatEnded() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MediaStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        // No process has an ID this high; this one is running.
        let ended = folder.appending(path: "UsualBot-playback-99999999")
        let running = folder.appending(path: "UsualBot-playback-1")
        for url in [ended, running] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        _ = store(ScriptedHTTP { _ in (200, "") }, temporaryDirectory: folder)

        #expect(!FileManager.default.fileExists(atPath: ended.path))
        #expect(FileManager.default.fileExists(atPath: running.path))
    }

    @Test func playingOfflineSaysTheFileIsNotHere() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MediaStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let media = MediaStore(auth: { nil }, temporaryDirectory: folder)
        await #expect(throws: GatewayError.disconnected) {
            try await media.playableFile(at: "/clip.mp4", profile: "ops")
        }
    }

    @Test func decodesOnlyBase64DataURLs() {
        #expect(MediaStore.decode(dataURL: "data:image/png;base64,iVBORw==") == Data(base64Encoded: "iVBORw=="))
        #expect(MediaStore.decode(dataURL: "data:text/plain,hello") == nil)
        #expect(MediaStore.decode(dataURL: "https://example.com/a.png") == nil)
    }
}
