import Testing

@testable import UsualUI

struct SetupCommandsTests {
    @Test func aBotsBrowserSetupNamesItsProfileAndRestartsLast() {
        let message = SetupCommands.askTurnOnBrowser(profile: "ops", name: "Ops")
        #expect(message.contains("`hermes -p ops config set browser.use_real_profile true`"))
        #expect(message.contains("Docker or SSH sandbox, stop and tell me"))
        let steps = message.components(separatedBy: "\n\n").filter { $0.first?.isNumber == true }
        #expect(steps.count == 2)
        #expect(steps.last?.contains("`hermes gateway restart`") == true)
    }

    @Test func theMainProfileTakesNoProfileFlag() {
        #expect(SetupCommands.turnOnBrowser(profile: "default").hasPrefix("hermes config set"))
        #expect(SetupCommands.turnOnBrowser(profile: "ops").hasPrefix("hermes -p ops config set"))
    }

    @Test func theOnePluginInstallsWithItsScript() {
        #expect(SetupCommands.install.contains("sh usual-bot/Integrations/install-usual-bot.sh"))
        #expect(SetupCommands.askInstall.contains("`sh usual-bot/Integrations/install-usual-bot.sh`"))
        #expect(SetupCommands.askInstall.contains("usual-bot plugin"))
    }
}
