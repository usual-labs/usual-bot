import HermesKit
import SwiftUI

extension Contact.Activity {
    /// The Machine row's value: what the Bot is doing, or that it's waiting on you.
    var label: String {
        switch self {
        case .idle: String(localized: "Idle")
        case .working: String(localized: "Working")
        case .needsYou: String(localized: "Needs you")
        }
    }
}

#if os(iOS)
    extension Theme {
        /// A grey page with lighter cards, like Settings, for the phone's room panel.
        static let groupedPage = Color(light: 0xF2F2F2, dark: 0x1F1F1F)
        static let groupedCard = Color(light: 0xFFFFFF, dark: 0x2A2A2A)
        static let groupedBorder = Color(light: 0xE6E6E6, dark: 0x363636)
    }

    /// The phone profile's rows: one for each page, with what's in it at a glance.
    struct PhoneProfileRows<Destination: View>: View {
        let contact: Contact
        let routines: RoutineList
        let skills: SkillList
        let apps: MCPServerList
        let vault: VaultList
        @ViewBuilder let destination: (ProfilePanel.Tab) -> Destination

        var body: some View {
            Section {
                ForEach(ProfilePanel.Tab.allCases, id: \.self) { tab in
                    // A link to its view, not a value: no destination to register on the chat's stack.
                    NavigationLink {
                        destination(tab)
                    } label: {
                        // The list moves the value under the name at accessibility sizes.
                        LabeledContent {
                            if let value = value(tab) { Text(value) }
                        } label: {
                            Label(tab.title, systemImage: icon(tab))
                        }
                    }
                }
            }
        }

        private func icon(_ tab: ProfilePanel.Tab) -> String {
            switch tab {
            case .routines: "clock"
            case .skills: "book.closed"
            case .apps: "square.grid.2x2"
            case .vault: "key"
            case .machine: "desktopcomputer"
            }
        }

        /// Nothing until the list has loaded, so a count is never a guess.
        private func value(_ tab: ProfilePanel.Tab) -> String? {
            switch tab {
            case .routines:
                guard routines.phase == .ready else { return nil }
                return Self.switchedOn(routines.routines.filter(\.isOn).count, of: routines.routines.count)
            case .skills:
                guard skills.phase == .ready else { return nil }
                return skills.skills.filter(\.enabled).count.formatted()
            case .apps:
                guard apps.phase == .ready else { return nil }
                return Self.switchedOn(apps.servers.filter(\.enabled).count, of: apps.servers.count)
            case .vault:
                guard vault.phase == .ready else { return nil }
                return vault.items.count.formatted()
            case .machine:
                return contact.activity.label
            }
        }

        /// "0 on" reads as a fault; say whether there are none at all, or all are off.
        private static func switchedOn(_ on: Int, of total: Int) -> String {
            if total == 0 { return String(localized: "None") }
            if on == 0 { return String(localized: "All off") }
            return String(localized: "\(on) on")
        }
    }
#endif
