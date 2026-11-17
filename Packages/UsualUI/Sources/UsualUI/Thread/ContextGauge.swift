import HermesKit
import SwiftUI

/// How full the chat's context is, always in view in the agent's profile: a bar, the numbers, and
/// Compress, which turns prominent once the context is filling up.
struct ContextGauge: View {
    let thread: ChatThread
    let usage: ChatUsage
    let context: ChatUsage.Context

    /// From here the bar turns amber and Compress is the prominent button. Hermes's own automatic
    /// threshold isn't reported, so the app doesn't name one.
    nonisolated static let fillingPercent = 70

    nonisolated static func isFilling(_ context: ChatUsage.Context) -> Bool { context.percent >= fillingPercent }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Context")
                Spacer(minLength: 8)
                Text(
                    "\(approx)\(ChatThread.tokens(context.used)) of \(ChatThread.tokens(context.max)) · \(approx)\(context.percent)%"
                )
                .zoomedFont(.subheadline)
                .monospacedDigit()
                .foregroundStyle(filling ? Theme.needsYouInk : Theme.secondaryInk)
            }
            bar
            HStack(alignment: .center, spacing: 8) {
                Group {
                    if thread.isCompressing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Compressing… summarizing older messages.")
                        }
                    } else {
                        details
                    }
                }
                .zoomedFont(.caption)
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !thread.isCompressing { compressButton }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var filling: Bool { Self.isFilling(context) }

    /// Plain shapes rather than `ProgressView`, whose bar takes no colour on the Mac.
    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.1))
                Capsule()
                    .fill(filling ? Theme.needsYouInk : Theme.ink.opacity(0.7))
                    .frame(width: proxy.size.width * min(max(CGFloat(context.percent) / 100, 0), 1))
                    .opacity(thread.isCompressing ? 0.5 : 1)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: context.percent)
        .accessibilityElement()
        .accessibilityLabel(Text("Context"))
        .accessibilityValue(Text("\(context.percent) percent full"))
    }

    /// The chat's totals, and how often it was compressed. `Text` with a key, so the counts inflect.
    private var details: Text {
        let totals = Text(
            "\(ChatThread.tokens(usage.input)) in, \(ChatThread.tokens(usage.output)) out, ^[\(usage.calls) call](inflect: true)"
        )
        guard usage.compressions > 0 else { return totals }
        return Text("\(totals) · compressed ^[\(usage.compressions) time](inflect: true)")
    }

    @ViewBuilder private var compressButton: some View {
        let button = Button("Compress") { Task { await thread.compress() } }
            .controlSize(.small)
            .disabled(!thread.canCompress)
            .help("Summarize the older part of this chat so the Bot has room again")
            .accessibilityHint(Text("Summarizes older messages so the Bot has room again"))
        if filling {
            button.buttonStyle(.clickable(.glassProminent)).tint(Theme.needsYouInk)
        } else {
            button.buttonStyle(.clickable(.glass))
        }
    }

    /// Hermes's own count rather than the provider's.
    private var approx: String { context.estimated ? "~" : "" }
}

/// How hard the Bot thinks in this chat, as a stepped slider over the levels, with the level's
/// name beside it and Make Default once it's set. Nothing set reads Default, with the knob faded at
/// Medium until you move it: the provider's own default isn't reported.
struct ThinkingControl: View {
    let thread: ChatThread
    let model: ChatModel
    let agentName: String

    /// Where the knob is while it's dragged: the level changes once, when you let go, not at every
    /// step it passes.
    @State private var draft: Double?
    @State private var isDragging = false

    private static let levels = ReasoningLevel.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Thinking")
                Spacer(minLength: 8)
                Text(ModelControls.levelName(model.reasoning))
                    .foregroundStyle(model.reasoning == nil ? Theme.secondaryInk : Theme.ink)
                if model.reasoning != nil {
                    Button {
                        Task { await thread.makeReasoningDefault() }
                    } label: {
                        Image(systemName: "pin")
                    }
                    .buttonStyle(.clickable(.borderless))
                    .foregroundStyle(Theme.secondaryInk)
                    .help("Make this \(agentName)'s default thinking")
                    .accessibilityLabel(Text("Make Default for \(agentName)"))
                }
            }
            Slider(value: index, in: 0...Double(Self.levels.count - 1), step: 1) {
                Text("Thinking")
            } minimumValueLabel: {
                Text("Off").zoomedFont(.caption).foregroundStyle(Theme.secondaryInk)
            } maximumValueLabel: {
                Text("Ultra").zoomedFont(.caption).foregroundStyle(Theme.secondaryInk)
            } onEditingChanged: { editing in
                isDragging = editing
                if !editing { commit() }
            }
            .opacity(model.reasoning == nil && draft == nil ? 0.6 : 1)
            .labelsHidden()
            .controlSize(.small)
            .help("How hard the Bot thinks in this chat")
            .accessibilityValue(Text(ModelControls.levelName(model.reasoning)))
        }
    }

    private var index: Binding<Double> {
        Binding(
            get: {
                draft ?? Double(Self.levels.firstIndex(of: model.reasoning ?? .medium) ?? 0)
            },
            set: { value in
                draft = value
                // The keyboard and VoiceOver step without a drag.
                if !isDragging { commit() }
            })
    }

    private func commit() {
        defer { draft = nil }
        guard let draft else { return }
        let level = Self.levels[min(max(Int(draft.rounded()), 0), Self.levels.count - 1)]
        if level != model.reasoning { thread.setReasoning(level) }
    }
}
