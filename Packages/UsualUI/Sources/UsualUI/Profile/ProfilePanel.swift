import HermesKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// The agent's card beside the chat: who it is, its routines, and the machine it runs on.
/// A trailing column on the Mac, a sheet on iPhone.
struct ProfilePanel: View {
    enum Tab: Hashable {
        case routines, machine
    }

    let contact: Contact
    let routines: RoutineList
    let gateway: GatewayAddress
    let link: AppModel.Link
    let gatewayDetails: GatewayDetails?
    let loadGatewayDetails: () async -> Void
    let close: () -> Void

    @State private var tab = Tab.routines

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                Picker("Show", selection: $tab) {
                    Text("Routines").tag(Tab.routines)
                    Text("Machine").tag(Tab.machine)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)

                switch tab {
                case .routines:
                    RoutinesView(list: routines, agentName: contact.name)
                case .machine:
                    MachineView(
                        details: contact.details, gateway: gateway, link: link, gatewayDetails: gatewayDetails,
                        load: loadGatewayDetails)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(Theme.pane, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close profile"))
            .padding(12)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            AgentAvatar(contact: contactWithoutActivity, size: 88)
            Text(contact.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            if let description = contact.details?.description {
                Text(description)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let profile = contact.details?.profile {
                Text("profile: \(profile)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Theme.selection, in: Capsule())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The panel's big avatar never pulses.
    private var contactWithoutActivity: Contact {
        var copy = contact
        copy.activity = .idle
        return copy
    }
}

// MARK: - Routines

private struct RoutinesView: View {
    let list: RoutineList
    let agentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch list.phase {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 20)
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await list.refresh() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .frame(maxWidth: .infinity)
            case .ready:
                if list.routines.isEmpty {
                    Text("No routines yet.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.vertical, 8)
                }
                ForEach(list.routines) { routine in
                    RoutineRow(routine: routine, list: list)
                    Divider().overlay(Theme.border)
                }
                if let problem = list.problem {
                    Text(problem)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.danger)
                        .padding(.top, 10)
                }
            }
            Text("New routine? Ask \(agentName) in chat, like “every Monday at 9, check our dependencies”.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Next-run times move on, and jobs can change from chat: keep the list fresh while it shows.
        .task(id: list.profile) {
            while !Task.isCancelled {
                await list.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

private struct RoutineRow: View {
    let routine: Routine
    let list: RoutineList

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                statusLine
                    .font(.system(size: 12.5))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { routine.isOn }, set: { list.setOn($0, for: routine) })) {
                Text(routine.name)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.ink)
            .disabled(routine.isFinished)
        }
        .padding(.vertical, 11)
    }

    /// The schedule in grey, the status after it in red when the last run failed.
    private var statusLine: Text {
        let status = RoutineStatus.status(for: routine)
        let schedule = Text(routine.schedule).foregroundStyle(Theme.secondaryInk)
        guard !status.isEmpty else { return schedule }
        let styled = Text(status).foregroundStyle(routine.lastRunFailed ? Theme.danger : Theme.secondaryInk)
        guard !routine.schedule.isEmpty else { return styled }
        return Text("\(schedule)\(Text(" · ").foregroundStyle(Theme.secondaryInk))\(styled)")
    }
}

/// "Weekdays at 08:00 · next tomorrow".
enum RoutineStatus {
    static func line(for routine: Routine, now: Date = .now) -> String {
        [routine.schedule, status(for: routine, now: now)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func status(for routine: Routine, now: Date = .now) -> String {
        if routine.isFinished { return String(localized: "Finished") }
        if !routine.isOn { return String(localized: "Paused") }
        let next = routine.nextRun.map {
            String(localized: "next \($0.formatted(.relative(presentation: .named, unitsStyle: .wide)))")
        }
        if routine.lastRunFailed {
            return [String(localized: "Last run failed"), next].compactMap { $0 }.joined(separator: " · ")
        }
        return next ?? ""
    }
}

// MARK: - Machine

private struct MachineView: View {
    let details: AgentDetails?
    let gateway: GatewayAddress
    let link: AppModel.Link
    let gatewayDetails: GatewayDetails?
    let load: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Agent") {
                row("Model", details?.model)
                row("Provider", details?.provider)
                row("Skills", details?.skillCount.map { String($0) })
            }
            section("Gateway") {
                row("Address", gateway.displayName)
                row("Version", gatewayDetails?.version)
                row("Status", statusText)
                row("Signed in as", gatewayDetails?.account)
            }
            #if os(macOS)
                if let settings = Self.hermesSettings {
                    Button("Open Hermes for advanced settings") { NSWorkspace.shared.open(settings) }
                        .buttonStyle(CardButtonStyle(primary: false))
                }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
    }

    private var statusText: String {
        switch link {
        case .connecting: return String(localized: "Connecting…")
        case .offline: return String(localized: "Offline")
        case .online:
            return gatewayDetails?.isHealthy == false
                ? String(localized: "Connected, some parts need attention")
                : String(localized: "Connected")
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                rows()
            }
        }
    }

    @ViewBuilder private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(Theme.secondaryInk)
                Text(value).foregroundStyle(Theme.ink).textSelection(.enabled)
            }
            .font(.system(size: 13.5))
        }
    }

    #if os(macOS)
        /// The official Hermes app's settings, when it's installed on this Mac.
        private static var hermesSettings: URL? {
            guard let url = URL(string: "hermes://open/settings"),
                NSWorkspace.shared.urlForApplication(toOpen: url) != nil
            else { return nil }
            return url
        }
    #endif
}
