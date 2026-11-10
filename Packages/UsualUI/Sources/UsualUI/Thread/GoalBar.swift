import HermesKit
import SwiftUI

/// The chat's goal above the message box: one line saying how it stands, with the one thing to do
/// about it, and the rest on a tap. It stays one line so the space above the message box, already
/// shared with background tasks and the queue, doesn't fill up at large text sizes.
///
/// Its Stop is "Stop Goal", never "Stop": the message box's own Stop ends one reply, and the goal
/// carries on after it.
struct GoalBar: View {
    let thread: ChatThread
    let goal: Goal
    let phase: GoalPhase
    let agentName: String
    @State private var isOpen = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(action: toggle) { line.accessibilityHidden(true) }
                    .buttonStyle(.plain)
                    // One button, not the spinner inside it: the spinner would give it its own role.
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, toggle)
                    .accessibilityLabel(Text(GoalWording.spoken(goal, phase, offline: !thread.isAttached)))
                    .accessibilityValue(Text(isOpen ? "Details shown" : "Details hidden"))
                    .accessibilityHint(Text("Shows or hides the whole goal and how it's going"))
                if !isOpen { action(GoalWording.mainAction(for: phase)) }
            }
            .frame(minHeight: 34)
            if isOpen { details }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.bottom, isOpen ? 10 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Goal"))
    }

    private func toggle() {
        withAnimation(.smooth(duration: 0.2)) { isOpen.toggle() }
    }

    private var line: some View {
        HStack(spacing: 8) {
            mark.frame(width: 16)
            Text(GoalWording.title(for: phase))
                .scaledFont(size: 12.5, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .fixedSize()
            // Open, the details below say both in full.
            if !isOpen {
                Text(goal.text)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            // The count gives way first: it's in the details, and the goal's words matter more.
            if !isOpen, !dynamicTypeSize.isAccessibilitySize, let note = sideNote {
                Text(note)
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.secondaryInk)
                    .monospacedDigit()
                    .fixedSize()
            }
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var mark: some View {
        switch phase {
        case .working: ProgressView().controlSize(.small)
        case .waiting: Image(systemName: "hourglass").foregroundStyle(Theme.secondaryInk)
        case .notRunning: Image(systemName: "pause.circle").foregroundStyle(Theme.secondaryInk)
        case .stopped: Image(systemName: "stop.circle").foregroundStyle(Theme.secondaryInk)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.online)
        }
    }

    private var sideNote: String? {
        if !thread.isAttached { return String(localized: "Offline") }
        guard phase == .working || phase == .waiting, goal.turnsAllowed > 0 else { return nil }
        return String(localized: "\(goal.turnsUsed) of \(goal.turnsAllowed)")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goal.text)
                .scaledFont(size: 13)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(GoalWording.details(goal, phase, agent: agentName, offline: !thread.isAttached), id: \.self) {
                Text($0)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                ForEach(GoalWording.actions(for: phase), id: \.self) { action($0) }
            }
        }
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func action(_ action: GoalWording.Action) -> some View {
        Button(action.label) {
            switch action {
            case .stop: thread.stopGoal()
            case .carryOn: thread.continueGoal()
            case .clear: thread.clearGoal()
            }
        }
        .buttonStyle(.clickable(.borderless))
        .scaledFont(size: 12, weight: .semibold)
        .fixedSize()
        .disabled(!isReady(action))
        .help(Text(thread.isAttached ? action.hint : String(localized: "Reconnect to your gateway to change the goal")))
        .accessibilityLabel(Text(action.spokenLabel))
        .accessibilityHint(Text(thread.isAttached ? action.hint : String(localized: "Not while offline")))
    }

    private func isReady(_ action: GoalWording.Action) -> Bool {
        // Continue starts a reply, so it waits for the one that's running.
        thread.canChangeGoal && (action != .carryOn || !thread.state.isRunning)
    }
}

/// What the goal bar says. Apart from the view so the words can be checked.
enum GoalWording {
    enum Action: Hashable {
        case stop, carryOn, clear

        var label: String {
            switch self {
            case .stop: String(localized: "Stop Goal")
            case .carryOn: String(localized: "Continue")
            case .clear: String(localized: "Clear")
            }
        }

        var spokenLabel: String {
            switch self {
            case .stop: String(localized: "Stop the goal")
            case .carryOn: String(localized: "Continue the goal")
            case .clear: String(localized: "Clear the goal")
            }
        }

        var hint: String {
            switch self {
            case .stop: String(localized: "Stops the goal and the reply that's running. You can continue it later.")
            case .carryOn: String(localized: "Carries on with the goal, with a full set of turns")
            case .clear: String(localized: "Removes the goal. The conversation stays.")
            }
        }
    }

    static func title(for phase: GoalPhase) -> String {
        switch phase {
        case .working: String(localized: "Goal")
        case .waiting: String(localized: "Goal waiting")
        case .notRunning: String(localized: "Goal not running")
        case .stopped: String(localized: "Goal stopped")
        case .done: String(localized: "Goal done")
        }
    }

    /// The one button on the closed bar.
    static func mainAction(for phase: GoalPhase) -> Action {
        switch phase {
        case .working, .waiting: .stop
        case .notRunning, .stopped: .carryOn
        case .done: .clear
        }
    }

    static func actions(for phase: GoalPhase) -> [Action] {
        switch phase {
        case .working, .waiting: [.stop]
        case .notRunning, .stopped: [.carryOn, .clear]
        case .done: [.clear]
        }
    }

    /// The closed bar for VoiceOver: state, the goal, and how far along.
    static func spoken(_ goal: Goal, _ phase: GoalPhase, offline: Bool) -> String {
        var parts = ["\(title(for: phase)): \(goal.text)"]
        if phase == .working || phase == .waiting, goal.turnsAllowed > 0 { parts.append(turns(goal)) }
        if offline { parts.append(String(localized: "Offline, so this is how it stood when last seen.")) }
        return parts.joined(separator: ". ")
    }

    /// The lines under the goal's words in the open bar: how it stands and why, how far along,
    /// what Hermes last made of it, and what else has to hold.
    static func details(_ goal: Goal, _ phase: GoalPhase, agent: String, offline: Bool) -> [String] {
        var lines: [String] = []
        switch phase {
        case .working:
            lines.append(
                String(
                    localized:
                        "\(agent) keeps working on this by itself. After each reply, Hermes checks whether it's done."
                ))
        case .waiting:
            lines.append(
                goal.waitingOn.map { String(localized: "Waiting for \($0). It goes on by itself after that.") }
                    ?? String(localized: "Waiting for something that's still running. It goes on by itself after that.")
            )
        case .notRunning:
            lines.append(
                String(localized: "Nothing is running for this goal. Continue picks it up, and so does a message.")
            )
        case .stopped:
            lines.append(goal.stopSentence)
        case .done:
            lines.append(
                goal.lastCheck.map { String(localized: "Hermes judged it done: \($0)") }
                    ?? String(localized: "Hermes judged it done."))
        }
        if goal.turnsAllowed > 0, phase != .done { lines.append(turns(goal)) }
        if phase == .working || phase == .waiting || phase == .notRunning, let check = goal.lastCheck {
            lines.append(String(localized: "Last check: \(check)"))
        }
        if !goal.criteria.isEmpty {
            lines.append(String(localized: "Also has to hold: \(goal.criteria.joined(separator: " · "))"))
        }
        if offline { lines.append(String(localized: "You're offline, so this is how it stood when last seen.")) }
        return lines
    }

    private static func turns(_ goal: Goal) -> String {
        String(localized: "\(goal.turnsUsed) of \(goal.turnsAllowed) turns used")
    }
}
