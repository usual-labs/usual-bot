import Foundation
import Testing

@testable import HermesKit

/// Which of Apple's push services a copy of the app uses, read from how it was signed.
struct PushRelayTests {
    /// A provisioning profile: a signed wrapper around a property list.
    private func profile(_ entitlements: [String: String]) throws -> Data {
        let list = try PropertyListSerialization.data(
            fromPropertyList: ["Name": "Test", "Entitlements": entitlements], format: .xml, options: 0)
        return Data([0x30, 0x80, 0x06, 0x09]) + list + Data([0x00, 0x00, 0xA0, 0x82])
    }

    @Test func testFlightAndAppStoreIPhoneBuildsHaveNoProfileAndUseProduction() {
        #expect(PushRelay.appleEnvironment(profile: nil) == "production")
    }

    @Test func developmentBuildsUseTheSandbox() throws {
        #expect(PushRelay.appleEnvironment(profile: try profile(["aps-environment": "development"])) == "sandbox")
        #expect(
            PushRelay.appleEnvironment(profile: try profile(["com.apple.developer.aps-environment": "development"]))
                == "sandbox")
    }

    @Test func distributionProfilesUseProduction() throws {
        #expect(PushRelay.appleEnvironment(profile: try profile(["aps-environment": "production"])) == "production")
        #expect(
            PushRelay.appleEnvironment(profile: try profile(["com.apple.developer.aps-environment": "production"]))
                == "production")
    }

    @Test func aProfileItCantReadMeansTheSandbox() {
        #expect(PushRelay.appleEnvironment(profile: Data("not a profile".utf8)) == "sandbox")
    }
}
