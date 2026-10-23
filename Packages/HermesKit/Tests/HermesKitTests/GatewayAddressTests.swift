import Foundation
import Testing

@testable import HermesKit

struct GatewayAddressTests {
    @Test func tailscaleAddressWithoutSchemeGetsHTTP() throws {
        let address = try GatewayAddress(parsing: " 100.101.102.103:9119/ ")
        #expect(address.baseURL.absoluteString == "http://100.101.102.103:9119")
        #expect(address.displayName == "100.101.102.103:9119")
    }

    @Test func publicHostWithoutSchemeGetsHTTPS() throws {
        #expect(
            try GatewayAddress(parsing: "hermes.example.com").baseURL.absoluteString == "https://hermes.example.com")
    }

    @Test func plainHTTPToPublicHostIsRefused() {
        #expect(throws: GatewayAddress.ParseError.insecureHTTP(host: "hermes.example.com")) {
            try GatewayAddress(parsing: "http://hermes.example.com")
        }
    }

    @Test(arguments: [
        "127.0.0.1", "10.0.0.5", "172.20.1.1", "192.168.1.10", "100.64.0.1", "100.127.255.255",
        "localhost", "mac-mini.local", "devbox", "::1", "fd7a:115c:a1e0::1",
    ])
    func privateHosts(host: String) {
        #expect(GatewayAddress.isPrivate(host: host))
    }

    @Test(arguments: [
        "8.8.8.8", "100.128.0.1", "172.32.0.1", "hermes.example.com", "box.tailnet.ts.net", "2001:db8::1",
    ])
    func publicHosts(host: String) {
        #expect(!GatewayAddress.isPrivate(host: host))
    }

    @Test(arguments: [
        ("100.101.102.103:9119", true), ("https://hermes.example-tailnet.ts.net", true),
        ("http://[fd7a:115c:a1e0::1]:9119", true),
        ("192.168.1.10:9119", false), ("hermes.example.com", false),
    ])
    func tailnetAddresses(input: String, isTailnet: Bool) throws {
        #expect(try GatewayAddress(parsing: input).isTailnet == isTailnet)
    }

    @MainActor @Test func unreachableTailnetGatewaySaysToCheckTailscale() throws {
        let error = GatewayError.unreachable("Could not connect to the server.")
        let tailnet = AppModel.describe(error, for: try GatewayAddress(parsing: "100.101.102.103:9119"))
        #expect(tailnet.contains("Tailscale is on"))
        let lan = AppModel.describe(error, for: try GatewayAddress(parsing: "192.168.1.10:9119"))
        #expect(lan == "Can't reach the gateway. Could not connect to the server.")
    }

    @Test func rejectsJunk() {
        #expect(throws: GatewayAddress.ParseError.empty) { try GatewayAddress(parsing: "  ") }
        #expect(throws: GatewayAddress.ParseError.invalid) { try GatewayAddress(parsing: "ftp://10.0.0.1") }
        #expect(throws: GatewayAddress.ParseError.invalid) { try GatewayAddress(parsing: "https://u:p@host.example") }
        #expect(throws: GatewayAddress.ParseError.invalid) { try GatewayAddress(parsing: "https://host.example/?a=1") }
    }

    @Test func keepsPathPrefixForEndpointsAndSocket() throws {
        let address = try GatewayAddress(parsing: "https://example.com/hermes/")
        #expect(address.url("/api/status").absoluteString == "https://example.com/hermes/api/status")
        #expect(address.webSocketURL(ticket: "t+1").absoluteString == "wss://example.com/hermes/api/ws?ticket=t+1")
        #expect(testGateway.webSocketURL(ticket: "abc").absoluteString == "ws://100.101.102.103:9119/api/ws?ticket=abc")
    }
}
