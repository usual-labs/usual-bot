import HermesKit
import SwiftUI

/// One quiet line that opens onto its rows.
struct FoldedRow<Label: View, Rows: View>: View {
    @ViewBuilder let label: Label
    @ViewBuilder let rows: Rows
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    label
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))

            if expanded {
                VStack(alignment: .leading, spacing: 6) { rows }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: Theme.bubbleWidth, alignment: .leading)
                    .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The turn's to-do list and helpers, while it runs.
struct LiveCards: View {
    let live: LiveActivity

    var body: some View {
        if !live.countedTodos.isEmpty {
            TodoLine(todos: live.countedTodos).transition(.settle)
        }
        if !live.helpers.isEmpty {
            HelperLine(helpers: live.helpers).transition(.settle)
        }
    }
}

/// The agent's to-do list while the turn runs.
private struct TodoLine: View {
    let todos: [LiveActivity.Todo]

    var body: some View {
        FoldedRow {
            Text(summary).lineLimit(1).padding(.leading, 12)
        } rows: {
            ForEach(todos) { todo in
                LiveRow(symbol: symbol(todo), tint: tint(todo), text: todo.text)
                    .accessibilityLabel(Text("\(state(todo)): \(todo.text)"))
            }
        }
    }

    private var summary: String {
        let done = todos.filter { $0.status == .done }.count
        let progress = String(localized: "\(done) of \(todos.count) done")
        guard let active = todos.first(where: { $0.status == .active }) else { return progress }
        return "\(progress) · \(active.text)"
    }

    private func symbol(_ todo: LiveActivity.Todo) -> String {
        switch todo.status {
        case .done: "checkmark.circle.fill"
        case .active: "circle.dotted"
        case .pending, .cancelled: "circle"
        }
    }

    private func tint(_ todo: LiveActivity.Todo) -> Color {
        todo.status == .done ? Theme.secondaryInk : Theme.ink
    }

    private func state(_ todo: LiveActivity.Todo) -> String {
        switch todo.status {
        case .done: String(localized: "Done")
        case .active: String(localized: "In progress")
        case .pending, .cancelled: String(localized: "To do")
        }
    }
}

/// The helpers this turn handed work to, as long as the turn runs.
private struct HelperLine: View {
    let helpers: [LiveActivity.Helper]

    var body: some View {
        FoldedRow {
            Text(summary).lineLimit(1).padding(.leading, 12)
        } rows: {
            ForEach(helpers) { helper in
                LiveRow(
                    symbol: symbol(helper), tint: helper.status == .failed ? Theme.danger : Theme.ink,
                    text: helper.goal, detail: detail(helper)
                )
                .accessibilityLabel(Text("\(state(helper)): \(helper.goal)"))
            }
        }
    }

    private var summary: String {
        let running = helpers.filter { $0.status == .running }
        let failed = helpers.filter { $0.status == .failed }.count
        var line: String
        switch (running.count, helpers.count) {
        case (0, 1): line = String(localized: "1 helper finished")
        case (0, let all): line = String(localized: "\(all) helpers finished")
        case (1, _): line = String(localized: "1 helper working")
        case (let count, _): line = String(localized: "\(count) helpers working")
        }
        if failed > 0 { line += " · " + String(localized: "\(failed) failed") }
        if let tool = running.last?.tool { line += " · " + ActivitySummary.doing(tool) }
        return line
    }

    private func detail(_ helper: LiveActivity.Helper) -> String? {
        guard let tool = helper.tool else { return nil }
        return [ActivitySummary.doing(tool), helper.detail].compactMap(\.self).joined(separator: " · ")
    }

    private func symbol(_ helper: LiveActivity.Helper) -> String {
        switch helper.status {
        case .running: "circle.dotted"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private func state(_ helper: LiveActivity.Helper) -> String {
        switch helper.status {
        case .running: String(localized: "Working")
        case .done: String(localized: "Finished")
        case .failed: String(localized: "Failed")
        }
    }
}

private struct LiveRow: View {
    let symbol: String
    let tint: Color
    let text: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).foregroundStyle(tint).lineLimit(2)
                if let detail {
                    Text(detail).foregroundStyle(Theme.secondaryInk).lineLimit(1)
                }
            }
        }
        .font(.system(size: 12.5))
        .accessibilityElement(children: .ignore)
    }
}
