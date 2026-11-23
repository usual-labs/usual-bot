import CryptoKit
import Foundation
import Testing

@testable import HermesKit

/// Opening the gateway's silent push that says a chat was read on another device.
struct ReadElsewhereTests {
    private let key = Data(repeating: 7, count: 32)

    private func seal(_ payload: [String: Any], with key: Data) throws -> String {
        let plain = try JSONSerialization.data(withJSONObject: payload)
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key))
        return try #require(box.combined).base64EncodedString()
    }

    @Test func opensTheChatThatWasRead() throws {
        let sealed = try seal(["kind": "read", "chat": "ada"], with: key)
        #expect(PushRelay.chatReadElsewhere(sealed: sealed, key: key) == .init(chat: "ada", gateway: nil))
    }

    @Test func saysWhichGatewayTheChatIsOn() throws {
        let sealed = try seal(["kind": "read", "chat": "default", "gateway": "home"], with: key)
        #expect(PushRelay.chatReadElsewhere(sealed: sealed, key: key) == .init(chat: "default", gateway: "home"))
    }

    @Test func aMessagePassedOffAsAClearOpensNothing() throws {
        let sealed = try seal(
            ["kind": "message", "chat": "ada", "title": "Ada", "body": "Hi", "sound": true], with: key)
        #expect(PushRelay.chatReadElsewhere(sealed: sealed, key: key) == nil)
    }

    @Test func anotherDevicesKeyOpensNothing() throws {
        let sealed = try seal(["kind": "read", "chat": "ada"], with: Data(repeating: 8, count: 32))
        #expect(PushRelay.chatReadElsewhere(sealed: sealed, key: key) == nil)
        #expect(PushRelay.chatReadElsewhere(sealed: "not sealed", key: key) == nil)
    }

    @Test func opensTheChatANotificationIsAbout() throws {
        let sealed = try seal(
            ["kind": "message", "chat": "ada", "gateway": "home", "title": "Ada", "body": "Hi", "sound": true],
            with: key)
        #expect(PushRelay.news(sealed: sealed, key: key) == .init(chat: "ada", gateway: "home"))
        let needsYou = try seal(["kind": "needs_you", "chat": "ada", "title": "Ada", "body": "?"], with: key)
        #expect(PushRelay.news(sealed: needsYou, key: key) == .init(chat: "ada", gateway: nil))
    }

    @Test func aClearOrATestIsNoNews() throws {
        #expect(PushRelay.news(sealed: try seal(["kind": "read", "chat": "ada"], with: key), key: key) == nil)
        #expect(
            PushRelay.news(sealed: try seal(["kind": "test", "title": "T", "body": "B"], with: key), key: key) == nil)
        #expect(PushRelay.news(in: ["kind": "test", "s": "x"]) == nil)
    }

    @Test func otherPushesAreNotClears() {
        #expect(PushRelay.chatReadElsewhere(in: ["kind": "message", "s": "x"]) == nil)
    }
}
