import HermesKit
import SwiftUI

/// One routine: what it does, when, where results go, Run Now, Edit, Delete and its past runs.
/// Editing and an opened run replace this page in the same sheet, with a way back.
struct RoutineDetail: View {
    private enum Page: Equatable {
        case overview
        case editing
        case run(RoutineRun)
    }

    let list: RoutineList
    let id: Routine.ID
    let agentName: String
    /// Just made from a template, to say so above it.
    var created: TemplateRoutine? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var page = Page.overview
    @State private var runs: [RoutineRun]?
    @State private var runsProblem: String?
    @State private var confirmingDelete = false
    @State private var deleteProblem: String?
    #if DEBUG
        @State private var openedFromLaunch = false
    #endif

    private var routine: Routine? { list.routines.first { $0.id == id } }

    var body: some View {
        Group {
            if let routine {
                switch page {
                case .overview: overview(routine)
                case .editing:
                    RoutineEditor(list: list, routine: routine, agentName: agentName) { _ in page = .overview }
                case .run(let run):
                    RoutineRunView(list: list, routine: routine, run: run, agentName: agentName) { page = .overview }
                }
            } else {
                // Deleted here or somewhere else while open.
                VStack(spacing: 12) {
                    Text("This routine is gone.").foregroundStyle(Theme.secondaryInk)
                    Button("Close") { dismiss() }.buttonStyle(.bordered)
                }
                .padding(40)
            }
        }
        #if os(macOS)
            .frame(width: 460, height: 560)
        #endif
    }

    private func overview(_ routine: Routine) -> some View {
        SheetForm(title: Text(routine.name), action: SheetAction(title: "Done") { dismiss() }) {
            Form {
                if let created {
                    Section { CreatedFromTemplate(made: created, agentName: agentName) }
                }
                Section { facts(routine) }
                Section { actions(routine) }
                pastRuns(routine)
            }
        }
        .task(id: routine.lastRun) {
            await loadRuns(routine)
            #if DEBUG
                openFromLaunch()
            #endif
        }
        .confirmationDialog(
            "Delete “\(routine.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete(routine) }
        } message: {
            Text("It stops running, and its past runs go with it. This can't be undone.")
        }
    }

    @ViewBuilder private func facts(_ routine: Routine) -> some View {
        Group {
            fact("When", RoutineSchedule.plainWords(routine.schedule) + statusSuffix(routine))
            if let prompt = routine.prompt.nonEmpty {
                fact("What to do", prompt)
            } else if routine.worksWithoutPrompt {
                fact("What to do", String(localized: "Runs a script or skills set up in Hermes."))
            }
            fact("Results", RoutineDescriptions.results(routine, profile: list.profile, agentName: agentName))
            if routine.lastRunFailed {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last run failed")
                        .scaledFont(size: 12, weight: .semibold)
                    if let error = routine.lastError {
                        Text(error).scaledFont(size: 13).textSelection(.enabled)
                    }
                }
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            } else if let error = routine.deliveryError {
                VStack(alignment: .leading, spacing: 3) {
                    Text("The last run worked, but its result wasn't posted")
                        .scaledFont(size: 12, weight: .semibold)
                    Text(error).scaledFont(size: 13).textSelection(.enabled)
                }
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func statusSuffix(_ routine: Routine) -> String {
        let status = RoutineStatus.status(for: routine, failure: false)
        return status.isEmpty ? "" : " · " + status
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Theme.secondaryInk)
            Text(value)
                .scaledFont(size: 14)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func actions(_ routine: Routine) -> some View {
        let isRunning = list.running.contains(routine.id)
        return VStack(alignment: .leading, spacing: 10) {
            // Wraps on a narrow sheet instead of squeezing the labels.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons(routine, isRunning: isRunning) }
                VStack(alignment: .leading, spacing: 8) { buttons(routine, isRunning: isRunning) }
            }
            if isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Running now. This can take a few minutes; you can close this and keep going.")
                }
                .scaledFont(size: 12.5)
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            } else if let outcome = list.outcomes[routine.id] {
                Text(outcome.message)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(outcome.succeeded ? Theme.secondaryInk : Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !routine.isOn && !routine.isFinished {
                Text("It's paused. Running it now turns it back on.")
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.secondaryInk)
            }
            if let deleteProblem {
                Text(deleteProblem)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func buttons(_ routine: Routine, isRunning: Bool) -> some View {
        Button(isRunning ? "Running…" : "Run Now") { list.runNow(routine) }
            .prominentButton()
            .disabled(isRunning)
            .accessibilityHint(Text("Runs it once now, as if it were time"))
        Button("Edit") { page = .editing }
            .buttonStyle(.bordered)
        Button("Delete…", role: .destructive) { confirmingDelete = true }
            .buttonStyle(.bordered)
    }

    private func pastRuns(_ routine: Routine) -> some View {
        Section("Past Runs") {
            if let runs {
                if runs.isEmpty {
                    Text("It hasn't run yet.")
                        .foregroundStyle(Theme.secondaryInk)
                }
                ForEach(runs) { run in
                    RunRow(run: run) { page = .run(run) }
                }
            } else if let runsProblem {
                Text(runsProblem).foregroundStyle(Theme.secondaryInk)
                Button("Try Again") { Task { await loadRuns(routine) } }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private func loadRuns(_ routine: Routine) async {
        do {
            runs = try await list.runs(of: routine)
            runsProblem = nil
        } catch {
            if runs == nil { runsProblem = RoutineList.describe(error) }
        }
    }

    #if DEBUG
        private func openFromLaunch() {
            guard !openedFromLaunch, let route = RoutinesView.launchRoute, route.first == id, route.count > 1 else {
                return
            }
            openedFromLaunch = true
            if route[1] == "start" {
                if let routine { list.runNow(routine) }
            } else if route[1] == "edit" {
                page = .editing
            } else if route[1] == "run", let run = runs?.first {
                page = .run(run)
            }
        }
    #endif

    private func delete(_ routine: Routine) {
        deleteProblem = nil
        Task {
            do {
                try await list.delete(routine)
                dismiss()
            } catch {
                deleteProblem = String(localized: "Couldn't delete it: \(RoutineList.describe(error))")
            }
        }
    }
}

private struct RunRow: View {
    let run: RoutineRun
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.started.formatted(date: .abbreviated, time: .shortened))
                        .scaledFont(size: 14)
                        .foregroundStyle(Theme.ink)
                    if let preview = run.preview {
                        Text(RoutineDescriptions.inline(preview))
                            .scaledFont(size: 12.5)
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text(RoutineDescriptions.status(run.status))
                    .scaledFont(size: 12.5, weight: .medium)
                    .foregroundStyle(run.status == .failed ? Theme.danger : Theme.secondaryInk)
                Image(systemName: "chevron.right")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        // A row that opens the run, as a list's navigation row: no button chrome.
        .buttonStyle(.clickable)
        .accessibilityElement(children: .combine)
    }
}

/// Routine facts in words, shared by the detail and the editor.
enum RoutineDescriptions {
    static func results(_ routine: Routine, profile: String, agentName: String) -> String {
        switch RoutineDelivery(deliver: routine.deliver, profile: profile) {
        case .thisChat:
            String(localized: "Posted in this chat, where \(agentName) reads it and replies.")
        case .pastRunsOnly:
            String(localized: "Kept in past runs only.")
        case .elsewhere(let raw):
            String(localized: "Sent to \(RoutineDelivery.places(raw, profile: profile)).")
        }
    }

    /// A preview's inline markdown (bold, code) styled rather than shown as asterisks.
    static func inline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    static func status(_ status: RoutineRun.Status) -> String {
        switch status {
        case .running: String(localized: "Running")
        case .finished: String(localized: "Finished")
        case .incomplete: String(localized: "Stopped early")
        case .failed: String(localized: "Failed")
        }
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
