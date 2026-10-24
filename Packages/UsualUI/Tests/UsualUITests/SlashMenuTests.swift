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

struct SlashWordTests {
    @Test func aSlashWordOpensTheMenuAnywhere() {
        #expect(MessageBox.slashWord(in: "/") == "")
        #expect(MessageBox.slashWord(in: "/rel") == "rel")
        #expect(MessageBox.slashWord(in: "clean this up with /cle") == "cle")
        #expect(MessageBox.slashWord(in: "first line\n/web") == "web")
    }

    @Test func aFinishedWordOrAPathDoesNot() {
        #expect(MessageBox.slashWord(in: "/retry ") == nil)
        #expect(MessageBox.slashWord(in: "see /usr/bin") == nil)
        #expect(MessageBox.slashWord(in: "and/or") == nil)
        #expect(MessageBox.slashWord(in: "") == nil)
    }
}
