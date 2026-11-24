#if os(macOS)
    import HermesKit
    import SwiftUI

    /// The commands the agent ran in this chat, oldest first, as a terminal would have shown them:
    /// each command, then what it printed and how it ended. Read only. A reloaded chat has the
    /// commands alone: Hermes's history keeps no tool's result.
    struct BotCommandsView: View {
        let agentName: String
        let state: ThreadState?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private var size: CGFloat { TerminalStyle.fontSize * Zoom.factor(dynamicTypeSize) }
        private var font: Font { Font(TerminalStyle.font(size: size)) }

        var body: some View {
            let commands = state?.commands ?? []
            if commands.isEmpty {
                Text("\(agentName) hasn't run any commands in this chat.")
                    .font(font)
                    .foregroundStyle(TerminalStyle.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(commands, id: \.step.id) { command in
                            row(command.step, date: command.date)
                        }
                    }
                    .padding(TerminalStyle.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
            }
        }

        private func row(_ step: ToolStep, date: Date?) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(dot(step.state))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    if let date {
                        Text(date, format: .dateTime.hour().minute())
                            .foregroundStyle(TerminalStyle.secondaryInk)
                    }
                    Text(verbatim: "$ \(step.commandLine)")
                        .foregroundStyle(TerminalStyle.ink)
                }
                if let output = step.output {
                    Text(verbatim: output)
                        .foregroundStyle(TerminalStyle.ink.opacity(0.75))
                        .padding(.leading, 14)
                }
                if let ending = ending(step) {
                    Text(ending)
                        .foregroundStyle(step.state == .failed ? Color(hex: 0xF0626A) : TerminalStyle.secondaryInk)
                        .padding(.leading, 14)
                }
            }
            .font(font)
            .accessibilityElement(children: .combine)
        }

        private func dot(_ state: ToolStep.State) -> Color {
            switch state {
            case .running: Theme.online
            case .done: TerminalStyle.secondaryInk
            case .failed: Color(hex: 0xF0626A)
            }
        }

        private func ending(_ step: ToolStep) -> LocalizedStringKey? {
            let seconds = step.duration.map { $0.formatted(.number.precision(.fractionLength(1))) }
            switch (step.state, step.exitCode, seconds) {
            case (.running, _, _): return step.progress.map { "Running · \($0)" } ?? "Running…"
            case (_, let code?, let seconds?): return "exit \(code) · \(seconds)s"
            case (_, let code?, nil): return "exit \(code)"
            case (.failed, nil, _): return "Failed"
            case (.done, nil, _): return nil
            }
        }
    }
#endif
