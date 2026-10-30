import Foundation
import Synchronization
import Testing

@testable import HermesKit

@MainActor
struct MediaStoreTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

    private func store(_ http: ScriptedHTTP) -> MediaStore {
        let auth = AuthSession(
            gateway: testGateway,
            tokens: TokenSet(
                accessToken: "a0", refreshToken: "r0", expiresAt: .now.addingTimeInterval(3600), provider: "nous",
                userID: "u1"),
            store: MemoryTokenStore(), http: http)
        return MediaStore(auth: { auth })
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

    @Test func decodesOnlyBase64DataURLs() {
        #expect(MediaStore.decode(dataURL: "data:image/png;base64,iVBORw==") == Data(base64Encoded: "iVBORw=="))
        #expect(MediaStore.decode(dataURL: "data:text/plain,hello") == nil)
        #expect(MediaStore.decode(dataURL: "https://example.com/a.png") == nil)
    }
}
