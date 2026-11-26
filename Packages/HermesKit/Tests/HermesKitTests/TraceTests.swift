import Foundation
import Testing

@testable import HermesKit

struct TraceTests {
    @Test func aTagIsTheSameAsTheGatewayPlugins() {
        // `tests/test_push_trace.py` checks the plugin's `tag("ada")` gives the same.
        #expect(Trace.tag("ada") == "fdee430d")
        #expect(Trace.tag("ada") != Trace.tag("grace"))
    }

    @Test func millisecondsRoundDown() {
        #expect(Trace.milliseconds(.seconds(2)) == 2000)
        #expect(Trace.milliseconds(.microseconds(1999)) == 1)
        #expect(Trace.milliseconds(.zero) == 0)
    }

    @Test func aReasonLeavesOutTheGatewaysWords() {
        #expect(Trace.reason(GatewayError.rpc(code: 4001, message: "your secret")) == "rpc4001")
        #expect(Trace.reason(GatewayError.http(status: 502, message: "Bad gateway at home")) == "http-502")
        #expect(Trace.reason(GatewayError.unreachable("100.101.102.103")) == "unreachable")
        #expect(Trace.reason(URLError(.timedOut)) == "url-1001")
        #expect(Trace.reason(CancellationError()) == "cancelled")
    }

    @Test func fieldsSkipEmptyParts() {
        #expect(Trace.fields("a=1", "", "b=2") == "a=1 b=2")
        #expect(Trace.since(nil) == "")
    }
}
