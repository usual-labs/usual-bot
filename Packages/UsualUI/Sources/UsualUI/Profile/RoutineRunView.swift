import HermesKit
import SwiftUI

/// One past run, read-only: the conversation of an agent run in the chat's bubbles, or what a
/// script-only run printed, which the gateway sends only the start of.
struct RoutineRunView: View {
    let list: RoutineList
    let routine: Routine
    let run: RoutineRun
    let agentName: String
    let back: () -> Void

    @State private var items: [TranscriptItem]?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: run.id) { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: back) {
                Label("Back", systemImage: "chevron.left")
                    .scaledFont(size: 13.5, weight: .medium)
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.clickable)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text("Back to \(routine.name)"))
            VStack(alignment: .leading, spacing: 1) {
                Text(routine.name)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1, accessibility: 3)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "\(run.started.formatted(date: .abbreviated, time: .shortened)) · \(RoutineDescriptions.status(run.status))"
                )
                .scaledFont(size: 12.5)
                .foregroundStyle(run.status == .failed ? Theme.danger : Theme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        if run.isScriptOnly {
            if let preview = run.preview {
                AgentBubble { MarkdownView(preview) }
            }
            Text("A script ran for this one. The gateway sends only the start of what it printed.")
                .scaledFont(size: 12.5)
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } else if let items {
            if items.isEmpty {
                Text(
                    run.status == .running
                        ? "It's still running. Nothing has been said yet." : "Nothing was said in this run."
                )
                .scaledFont(size: 13.5)
                .foregroundStyle(Theme.secondaryInk)
            }
            ForEach(items) { item in
                ItemView(item: item, agentName: agentName)
            }
        } else if let problem {
            VStack(alignment: .leading, spacing: 6) {
                Text(problem).foregroundStyle(Theme.secondaryInk)
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.clickable)
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
            }
            .scaledFont(size: 13)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 20)
        }
    }

    private func load() async {
        guard !run.isScriptOnly else { return }
        do {
            items = try await list.transcript(of: run)
            problem = nil
        } catch {
            problem = String(localized: "Couldn't open this run: \(RoutineList.describe(error))")
        }
    }
}
