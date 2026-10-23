import HermesKit
import SwiftUI
import Testing

@testable import UsualUI

struct SlashMenuTests {
    private let commands = SlashCommands(
        list: [
            SlashCommand(name: "/web-research", description: "", kind: .skill),
            SlashCommand(name: "/release-notes", description: "", kind: .skill),
            SlashCommand(name: "/retry", description: "", kind: .command),
            SlashCommand(name: "/research-brief", description: "", kind: .skill),
        ], load: {}, prefill: .constant(nil))

    @Test func namesStartingWithTheQueryComeFirst() {
        #expect(
            commands.matching("re").map(\.name) == ["/release-notes", "/retry", "/research-brief", "/web-research"])
        #expect(commands.matching("research").map(\.name) == ["/research-brief", "/web-research"])
        #expect(commands.matching("").count == 4)
        #expect(commands.matching("zzz").isEmpty)
    }
}
