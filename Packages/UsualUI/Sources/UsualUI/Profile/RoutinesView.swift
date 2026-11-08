import HermesKit
import SwiftUI

/// The agent's routines: each one's schedule, switch and last result, and New Routine. Opening one
/// shows its detail in a sheet.
struct RoutinesView: View {
    let list: RoutineList
    let agentName: String
    /// The Mac panel's Bot and tabs, above the page.
    var top: AnyView? = nil

    @State private var sheet: RoutineSheet?

    var body: some View {
        ProfileForm(top: top) {
            Section {
                switch list.phase {
                case .loading:
                    ProfileLoading()
                case .failed(let message):
                    ProfileFailure(message: message) { await list.refresh() }
                case .ready:
                    if list.routines.isEmpty {
                        Text(
                            "No routines yet. A routine has \(agentName) do something on a schedule, like every weekday at 9."
                        )
                        .foregroundStyle(.secondary)
                    }
                    ForEach(list.routines) { routine in
                        RoutineRow(routine: routine, list: list) { sheet = .routine(routine.id) }
                    }
                    if let problem = list.problem {
                        Text(problem).foregroundStyle(Theme.danger)
                    }
                }
            } header: {
                ProfileSectionHeader("Scheduled") {
                    Button("New Routine", systemImage: "plus") { sheet = .new }
                        .help("New Routine")
                        .disabled(list.phase != .ready)
                }
            } footer: {
                Text("You can also ask \(agentName) in chat, like “every Monday at 9, check our dependencies”.")
            }
        }
        // Next-run times move on, and jobs can change from chat: keep the list fresh while it shows.
        .task(id: list.profile) {
            while !Task.isCancelled {
                await list.refresh()
                // Ready before New Routine opens, so a gateway without templates goes straight to
                // the blank form.
                if list.phase == .ready { await list.loadTemplates() }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        #if DEBUG
            .task(id: "\(list.phase) \(list.templatePhase)") { openFromLaunch() }
        #endif
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .new:
                    NewRoutineSheet(list: list, agentName: agentName) { self.sheet = nil }
                case .routine(let id):
                    RoutineDetail(list: list, id: id, agentName: agentName)
                }
            }
            .environment(\.mediaProfile, list.profile)
        }
    }
}

#if DEBUG
    extension RoutinesView {
        /// `USUALBOT_OPEN_ROUTINE=new`, `=new/<template key>`, `=<id>`, `=<id>/edit`, `=<id>/run` (its
        /// latest run) or `=<id>/start` (Run Now) opens that sheet once the list loads, for
        /// screenshots without clicking.
        static let launchRoute = ProcessInfo.processInfo.environment["USUALBOT_OPEN_ROUTINE"]?
            .split(separator: "/").map(String.init)

        fileprivate func openFromLaunch() {
            guard let route = Self.launchRoute, list.phase == .ready, sheet == nil else { return }
            if route.first == "new" {
                // A template's form waits for the templates.
                guard route.count == 1 || list.templatePhase != .loading else { return }
                sheet = .new
            } else if let id = route.first, list.routines.contains(where: { $0.id == id }) {
                sheet = .routine(id)
            }
        }
    }
#endif

/// What the routine sheet shows.
enum RoutineSheet: Identifiable, Hashable {
    case new
    case routine(Routine.ID)

    var id: Self { self }
}

private struct RoutineRow: View {
    let routine: Routine
    let list: RoutineList
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Plain, so a tap on the switch doesn't open the routine too: a list row runs every
            // bordered button in it.
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    RoutineStatus.text(for: routine, isRunning: list.running.contains(routine.id))
                        .font(.subheadline)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.clickable)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Shows the routine, its past runs and what you can change"))
            Toggle(isOn: Binding(get: { routine.isOn }, set: { list.setOn($0, for: routine) })) {
                Text(routine.name)
            }
            .labelsHidden()
            .disabled(routine.isFinished)
        }
    }
}

/// "Weekdays at 8:00 AM · next tomorrow", with a failed last run in red and its reason after.
enum RoutineStatus {
    static func text(for routine: Routine, isRunning: Bool, now: Date = .now) -> Text {
        let schedule = Text(RoutineSchedule.plainWords(routine.schedule)).foregroundStyle(Theme.secondaryInk)
        let dot = Text(" · ").foregroundStyle(Theme.secondaryInk)
        if isRunning { return Text("\(schedule)\(dot)\(Text("Running now…").foregroundStyle(Theme.ink))") }
        let status = status(for: routine, now: now)
        guard !status.isEmpty else { return schedule }
        let styled = Text(status).foregroundStyle(routine.lastRunFailed ? Theme.danger : Theme.secondaryInk)
        guard !routine.schedule.isEmpty else { return styled }
        return Text("\(schedule)\(dot)\(styled)")
    }

    /// `failure`: whether a failed last run is part of it, as in the list. The detail says it apart.
    static func status(for routine: Routine, failure: Bool = true, now: Date = .now) -> String {
        if routine.isFinished { return String(localized: "Finished") }
        if !routine.isOn { return String(localized: "Paused") }
        let next = routine.nextRun.map {
            String(localized: "next \($0.formatted(.relative(presentation: .named, unitsStyle: .wide)))")
        }
        if failure, routine.lastRunFailed {
            let failed = routine.lastError.map { String(localized: "Last run failed: \($0)") }
            return [failed ?? String(localized: "Last run failed"), next].compactMap { $0 }.joined(separator: " · ")
        }
        if failure, routine.deliveryError != nil {
            return [String(localized: "Last result wasn't posted"), next].compactMap { $0 }.joined(separator: " · ")
        }
        return next ?? ""
    }
}
