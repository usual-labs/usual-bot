import Foundation
import Testing

@testable import HermesKit

@MainActor
struct BotPicturesTests {
    /// The start of a PNG `width` × `height`: enough for the size check.
    private func png(_ width: UInt32, _ height: UInt32) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
        data.append(contentsOf: Array("IHDR".utf8))
        for value in [width, height] { data.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init)) }
        data.append(contentsOf: [8, 6, 0, 0, 0])
        return data
    }

    private func asset(_ data: Data) -> JSONValue {
        ["found": true, "mime": "image/png", "data": .string("data:image/png;base64," + data.base64EncodedString())]
    }

    private func scout(revision: Int, isPhoto: Bool = true) -> Contact {
        Contact(
            id: "scout", name: "Scout", details: AgentDetails(profile: "scout"),
            picture: Contact.Picture(revision: revision, isPhoto: isPhoto))
    }

    private func channel(_ gateway: ScriptedGateway) async -> JSONRPCChannel {
        let channel = JSONRPCChannel(socket: gateway.socket)
        await channel.start()
        return channel
    }

    @Test func readsAPictureOncePerRevision() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        let pictures = BotPictures()
        let first = png(256, 256)

        pictures.refresh([scout(revision: 1), Contact(id: "ops", name: "Ops")], on: channel)
        let params = try await gateway.answer(0, method: "profiles.get_asset", result: asset(first))
        #expect(params == ["name": "scout", "asset": "avatar"])
        try await waitUntilOnMain { pictures.data(for: "scout") == first }
        #expect(pictures.data(for: "ops") == nil)  // No picture: no request, the app's character.

        pictures.refresh([scout(revision: 1)], on: channel)  // The roster's next tick: nothing to read.
        let second = png(256, 255)
        pictures.refresh([scout(revision: 2)], on: channel)  // The look changed.
        _ = try await gateway.answer(1, method: "profiles.get_asset", result: asset(second))
        try await waitUntilOnMain { pictures.data(for: "scout") == second }
        #expect(gateway.socket.sent.count == 2)
    }

    @Test func aStillOfTheDrawnFaceIsNotAPicture() async throws {
        let gateway = ScriptedGateway()
        let channel = await channel(gateway)
        let pictures = BotPictures()
        let face = png(160, 160)

        pictures.refresh([scout(revision: 1, isPhoto: false)], on: channel)
        _ = try await gateway.answer(0, method: "profiles.get_asset", result: asset(face))
        // sleep-ok: the picture should stay unset, so there is no event to wait for
        try await Task.sleep(for: .milliseconds(50))
        #expect(pictures.data(for: "scout") == nil)

        // Marked a photo, the same size is the user's picture after all.
        pictures.refresh([scout(revision: 2, isPhoto: true)], on: channel)
        _ = try await gateway.answer(1, method: "profiles.get_asset", result: asset(face))
        try await waitUntilOnMain { pictures.data(for: "scout") == face }
    }

    @Test func cachedPicturesAreReadAgainAndRemovedOnesForgotten() async throws {
        let gateway = ScriptedGateway()
        let pictures = BotPictures()
        pictures.restore([
            "scout": .init(revision: 3, data: png(256, 256)), "gone": .init(revision: 1, data: png(64, 64)),
        ])

        let channel = await channel(gateway)
        pictures.refresh([scout(revision: 3)], on: channel)
        #expect(pictures.data(for: "gone") == nil)  // The agent was deleted.
        let fresh = png(200, 200)
        _ = try await gateway.answer(0, method: "profiles.get_asset", result: asset(fresh))  // Restored isn't read.
        try await waitUntilOnMain { pictures.data(for: "scout") == fresh }

        pictures.refresh([Contact(id: "scout", name: "Scout")], on: channel)  // Picture removed in the official app.
        #expect(pictures.data(for: "scout") == nil)
    }

    @Test func onlyA160PixelPNGIsTheDrawnFace() {
        #expect(BotPictures.isDrawnFace(png(160, 160)))
        #expect(!BotPictures.isDrawnFace(png(256, 256)))
        #expect(!BotPictures.isDrawnFace(Data([0xFF, 0xD8, 0xFF] + Array(repeating: 0, count: 30))))  // JPEG.
        #expect(!BotPictures.isDrawnFace(Data()))
    }
}
