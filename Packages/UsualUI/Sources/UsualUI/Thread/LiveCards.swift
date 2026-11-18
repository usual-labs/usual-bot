import HermesKit
import SwiftUI

/// One quiet line that opens onto its rows: an icon, what happened and a chevron. Tool activity,
/// to-do lists, helpers and Hermes's own results all fold this way, so they look and open alike.
/// The rows hang off a thin rail under the icon rather than sitting in a card of their own, so
/// they read as belonging to their line.
struct FoldedRow<Label: View, Rows: View>: View {
    /// Before the label; `nil` when the label brings its own, as the working avatar does.
    var symbol: String? = nil
    var tint: Color = Theme.secondaryInk
    /// `false` for a line with nothing behind it: no chevron, and it doesn't open.
    var opens = true
    /// Open until you fold it, as a run of steps is while it runs. Its line folds once this turns
    /// `false`, unless you opened it yourself.
    var openByDefault = false
    @ViewBuilder let label: Label
    @ViewBuilder let rows: Rows
    @State private var chosen: Bool?
    private var expanded: Bool { chosen ?? openByDefault }
    @ScaledSize(relativeTo: .footnote) private var iconWidth: CGFloat = 16

    private static var iconInset: CGFloat { 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if opens {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { chosen = !expanded }
                } label: {
                    line
                }
                .buttonStyle(.clickable)
                .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
            } else {
                line
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6) { rows }
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.secondaryInk.opacity(0.35)).frame(width: 1.5)
                    }
                    .padding(.leading, Self.iconInset + iconWidth / 2)
                    .zoomedFrame(maxWidth: Theme.bubbleWidth, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var line: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .scaledFont(size: 12)
                    .foregroundStyle(tint)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
            }
            label
            if opens {
                Image(systemName: "chevron.right")
                    .scaledFont(size: 10, weight: .semibold)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, symbol == nil ? 0 : Self.iconInset)
        .scaledFont(size: 13)
        .foregroundStyle(Theme.secondaryInk)
        .zoomedFrame(minHeight: 28)
        .contentShape(Rectangle())
    }
}

/// The turn's to-do list and helpers, while it runs.
struct LiveCards: View {
    let live: LiveActivity

    var body: some View {
        ProgressLines(todos: live.countedTodos, helpers: live.helpers)
    }
}

/// A to-do list and helpers: the running turn's, or those a finished turn kept in its place.
struct ProgressLines: View {
    let todos: [LiveActivity.Todo]
    let helpers: [LiveActivity.Helper]

    var body: some View {
        // When the turn ends the same lines become a transcript item, so they leave without a fade.
        if !todos.isEmpty {
            TodoLine(todos: todos).transition(.asymmetric(insertion: .settle, removal: .identity))
        }
        if !helpers.isEmpty {
            HelperLine(helpers: helpers).transition(.asymmetric(insertion: .settle, removal: .identity))
        }
    }
}

/// The agent's to-do list while the turn runs.
private struct TodoLine: View {
    let todos: [LiveActivity.Todo]

    var body: some View {
        FoldedRow(symbol: "checklist") {
            Text(summary).lineLimit(1)
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
        FoldedRow(
            symbol: failed ? "xmark.circle" : "arrow.triangle.branch",
            tint: failed ? Theme.danger : Theme.secondaryInk
        ) {
            Text(summary).lineLimit(1)
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

    private var failed: Bool { helpers.contains { $0.status == .failed } }

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
                .scaledFont(size: 11)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).foregroundStyle(tint).lineLimit(2)
                if let detail {
                    Text(detail).foregroundStyle(Theme.secondaryInk).lineLimit(1)
                }
            }
        }
        .scaledFont(size: 12.5)
        .accessibilityElement(children: .ignore)
    }
}
