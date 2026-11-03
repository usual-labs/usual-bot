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
        /// Grok's grouped look for the phone profile: a grey page with lighter cards, like Settings.
        static let groupedPage = Color(light: 0xF2F2F2, dark: 0x1F1F1F)
        static let groupedCard = Color(light: 0xFFFFFF, dark: 0x2A2A2A)
        static let groupedBorder = Color(light: 0xE6E6E6, dark: 0x363636)
    }

    /// The phone profile's card: a row for each page, with what's in it at a glance.
    struct PhoneProfileRows<Destination: View>: View {
        let contact: Contact
        let routines: RoutineList
        let skills: SkillList
        let apps: MCPServerList
        let vault: VaultList
        @ViewBuilder let destination: (ProfilePanel.Tab) -> Destination

        var body: some View {
            VStack(spacing: 0) {
                ForEach(Array(ProfilePanel.Tab.allCases.enumerated()), id: \.element) { index, tab in
                    if index > 0 { Divider().padding(.leading, 56) }
                    // A link to its view, not a value: no destination to register on the chat's stack.
                    NavigationLink {
                        destination(tab)
                    } label: {
                        row(tab)
                    }
                    .buttonStyle(.clickable)
                }
            }
            .background(Theme.groupedCard, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.groupedBorder))
        }

        private func row(_ tab: ProfilePanel.Tab) -> some View {
            HStack(spacing: 14) {
                Image(systemName: icon(tab))
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let value = value(tab) {
                    Text(value)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.secondaryInk)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
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
