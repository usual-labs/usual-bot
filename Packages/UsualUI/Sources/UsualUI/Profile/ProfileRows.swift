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
#endif

/// The profile's pages as rows, one each, with what's in it at a glance: on iPhone each pushes its
/// page, as in Settings; in the Mac panel each opens it in place, with a way back. Rows replaced the
/// Mac's five tabs (November 2026), which no longer fit the panel's narrowest width.
struct ProfileRows<Destination: View>: View {
    let contact: Contact
    let routines: RoutineList
    let skills: SkillList
    let apps: MCPServerList
    let vault: VaultList
    /// The Mac opens a page in the panel.
    var open: (ProfilePanel.Tab) -> Void = { _ in }
    /// iPhone pushes the page.
    @ViewBuilder let destination: (ProfilePanel.Tab) -> Destination

    var body: some View {
        Section {
            ForEach(ProfilePanel.Tab.allCases, id: \.self) { tab in
                #if os(iOS)
                    // A link to its view, not a value: no destination to register on the chat's stack.
                    NavigationLink {
                        destination(tab)
                    } label: {
                        label(tab)
                    }
                #else
                    Button {
                        open(tab)
                    } label: {
                        HStack(spacing: 6) {
                            label(tab)
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.clickable)
                    .foregroundStyle(Theme.ink)
                    .accessibilityHint(Text("Opens \(Text(tab.title))"))
                #endif
            }
        } header: {
            ProfileSectionHeader("Bot")
        }
    }

    private func label(_ tab: ProfilePanel.Tab) -> some View {
        // The list moves the value under the name at accessibility sizes.
        LabeledContent {
            if let value = value(tab) { Text(value).foregroundStyle(Theme.secondaryInk) }
        } label: {
            Label(tab.title, systemImage: icon(tab))
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

/// The routines that run soonest, with their switches, under the profile's rows. The whole list is
/// on the Routines page; on the Mac a row here opens it. On iPhone the rows only switch: a list row
/// that both pushes and holds a switch takes taps meant for the switch.
struct NextRoutines: View {
    let routines: RoutineList
    var open: () -> Void = {}

    nonisolated static var count: Int { 2 }

    /// Switched-on routines with a next run, soonest first.
    nonisolated static func soonest(_ routines: [Routine], count: Int = count) -> [Routine] {
        Array(
            routines.filter { $0.isOn && !$0.isFinished && $0.nextRun != nil }
                .sorted { ($0.nextRun ?? .distantFuture) < ($1.nextRun ?? .distantFuture) }
                .prefix(count))
    }

    var body: some View {
        let next = routines.phase == .ready ? Self.soonest(routines.routines) : []
        if !next.isEmpty {
            Section {
                ForEach(next) { routine in
                    HStack(spacing: 12) {
                        link(routine)
                        Toggle(isOn: Binding(get: { routine.isOn }, set: { routines.setOn($0, for: routine) })) {
                            Text(routine.name)
                        }
                        .labelsHidden()
                    }
                }
            } header: {
                ProfileSectionHeader("Next Up")
            }
        }
    }

    @ViewBuilder private func link(_ routine: Routine) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(routine.name).foregroundStyle(Theme.ink).lineLimit(2)
            if let next = routine.nextRun {
                Text(next.formatted(.relative(presentation: .named, unitsStyle: .wide)).capitalizedFirst)
                    .zoomedFont(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        #if os(iOS)
            label
        #else
            // Plain, so a click on the switch doesn't open the page too.
            Button(action: open) { label }
                .buttonStyle(.clickable)
                .accessibilityHint(Text("Opens Routines"))
        #endif
    }
}

extension String {
    /// "In 19 hours" from "in 19 hours", for a line that starts with it.
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
