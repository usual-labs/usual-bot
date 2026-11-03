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
                    Button("Close") { dismiss() }.buttonStyle(CardButtonStyle(primary: false))
                }
                .padding(40)
            }
        }
        .frame(minWidth: 340, idealWidth: 460, maxWidth: 560, minHeight: 460)
        .background(Theme.window)
    }

    private func overview(_ routine: Routine) -> some View {
        SheetForm(title: Text(routine.name), action: SheetAction(title: "Done") { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let created { CreatedFromTemplate(made: created, agentName: agentName) }
                    facts(routine)
                    actions(routine)
                    pastRuns(routine)
                }
                .padding(20)
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

    private func facts(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                        .font(.system(size: 12, weight: .semibold))
                    if let error = routine.lastError {
                        Text(error).font(.system(size: 13)).textSelection(.enabled)
                    }
                }
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            } else if let error = routine.deliveryError {
                VStack(alignment: .leading, spacing: 3) {
                    Text("The last run worked, but its result wasn't posted")
                        .font(.system(size: 12, weight: .semibold))
                    Text(error).font(.system(size: 13)).textSelection(.enabled)
                }
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusSuffix(_ routine: Routine) -> String {
        let status = RoutineStatus.status(for: routine, failure: false)
        return status.isEmpty ? "" : " · " + status
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
            Text(value)
                .font(.system(size: 14))
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
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            } else if let outcome = list.outcomes[routine.id] {
                Text(outcome.message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(outcome.succeeded ? Theme.secondaryInk : Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !routine.isOn && !routine.isFinished {
                Text("It's paused. Running it now turns it back on.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
            }
            if let deleteProblem {
                Text(deleteProblem)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func buttons(_ routine: Routine, isRunning: Bool) -> some View {
        Button(isRunning ? "Running…" : "Run Now") { list.runNow(routine) }
            .buttonStyle(CardButtonStyle(primary: true))
            .disabled(isRunning)
            .accessibilityHint(Text("Runs it once now, as if it were time"))
        Button("Edit") { page = .editing }
            .buttonStyle(CardButtonStyle(primary: false))
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            // Inside the label, or the button style's ink wins.
            Text("Delete").foregroundStyle(Theme.danger)
        }
        .buttonStyle(CardButtonStyle(primary: false))
    }

    private func pastRuns(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Past Runs")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            if let runs {
                if runs.isEmpty {
                    Text("It hasn't run yet.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.vertical, 8)
                }
                ForEach(runs) { run in
                    RunRow(run: run) { page = .run(run) }
                    Divider().overlay(Theme.border)
                }
            } else if let runsProblem {
                VStack(alignment: .leading, spacing: 6) {
                    Text(runsProblem).foregroundStyle(Theme.secondaryInk)
                    Button("Try Again") { Task { await loadRuns(routine) } }
                        .buttonStyle(.clickable)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                }
                .font(.system(size: 13))
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 16)
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
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink)
                    if let preview = run.preview {
                        Text(RoutineDescriptions.inline(preview))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text(RoutineDescriptions.status(run.status))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(run.status == .failed ? Theme.danger : Theme.secondaryInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
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
