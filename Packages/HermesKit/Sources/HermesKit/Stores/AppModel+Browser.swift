import Foundation

extension AppModel {
    /// `contact`'s browser. Call `BotBrowser.refresh()` to learn whether it has one to watch.
    public func browser(for contact: Contact) -> BotBrowser {
        if let browser = browsers[contact.id] { return browser }
        let profile = contact.details?.profile ?? contact.id
        #if DEBUG
            if isDemo {
                let browser = BotBrowser.demo(profile: profile)
                browsers[contact.id] = browser
                return browser
            }
        #endif
        let browser = BotBrowser(profile: profile, auth: { [weak self] in self?.auth }, makeSocket: makeScreenSocket)
        browsers[contact.id] = browser
        return browser
    }
}
