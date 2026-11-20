import Foundation

extension AppModel {
    /// `contact`'s shell. Call `BotTerminal.refresh()` to learn whether it has one to open.
    public func terminal(for contact: Contact) -> BotTerminal {
        if let terminal = terminals[contact.id] { return terminal }
        let profile = contact.details?.profile ?? contact.id
        #if DEBUG
            if isDemo {
                let terminal = BotTerminal.demo(profile: profile)
                terminals[contact.id] = terminal
                return terminal
            }
        #endif
        let terminal = BotTerminal(profile: profile, auth: { [weak self] in self?.auth }, makeSocket: makeScreenSocket)
        terminals[contact.id] = terminal
        return terminal
    }
}
