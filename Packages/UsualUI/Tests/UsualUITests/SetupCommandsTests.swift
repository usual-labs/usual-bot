import Testing

@testable import UsualUI

struct SetupCommandsTests {
    @Test func aBotsBrowserSetupNamesItsProfileAndRestartsLast() {
        let message = SetupCommands.askTurnOnBrowser(profile: "ops", name: "Ops")
        #expect(message.contains("`hermes -p ops config set browser.use_real_profile true`"))
        #expect(message.contains("Docker or SSH sandbox, stop and tell me"))
        let steps = message.components(separatedBy: "\n\n").filter { $0.first?.isNumber == true }
        #expect(steps.count == 4)
        #expect(steps.last?.contains("`hermes gateway restart`") == true)
    }

    @Test func theMainProfileTakesNoProfileFlag() {
        #expect(SetupCommands.turnOnBrowser(profile: "default").hasPrefix("hermes config set"))
        #expect(SetupCommands.turnOnBrowser(profile: "ops").hasPrefix("hermes -p ops config set"))
    }

    @Test func eachPluginInstallsWithItsOwnScript() {
        #expect(SetupCommands.install(.push).contains("Integrations/hermes-push/install.sh"))
        #expect(SetupCommands.askInstall(.browser).contains("Integrations/hermes-browser/install.sh"))
    }
}
