import Foundation

extension AppModel {
    /// `contact`'s computer. Call `BotScreen.refresh()` to learn whether it has one.
    public func screen(for contact: Contact) -> BotScreen {
        if let screen = screens[contact.id] { return screen }
        let profile = contact.details?.profile ?? contact.id
        #if DEBUG
            if isDemo {
                let screen = BotScreen.demo(profile: profile)
                screens[contact.id] = screen
                return screen
            }
        #endif
        let screen = BotScreen(
            profile: profile, channel: { [weak self] in self?.channel },
            gateway: { [weak self] in self?.auth?.gateway },
            makeSocket: makeScreenSocket)
        screens[contact.id] = screen
        return screen
    }
}
