import HermesKit
import SwiftUI

/// What the message box needs to offer a chat's model, thinking and context. iPhone only: the Mac
/// shows them under the box (ModelControls).
struct ChatControls {
    let thread: ChatThread
    let agentName: String
    /// The agent's default model, for Make Default.
    let agentDefault: AgentDetails?
}

#if os(iOS)
    /// The iPhone message box's row of `+`, text and buttons. While you type it splits: the text
    /// takes the whole width and the buttons move to a row of their own below it. One layout keeps
    /// each view's identity, so the field keeps its focus and `+` its open picker as it changes.
    struct ComposerLayout: Layout {
        var expanded: Bool
        var spacing: CGFloat = 8
        var rowSpacing: CGFloat = 4

        enum Role { case leading, text, trailing }
        struct RoleKey: LayoutValueKey { static let defaultValue = Role.text }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            frames(width: proposal.width ?? 320, subviews: subviews).size
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let layout = frames(width: bounds.width, subviews: subviews)
            for (subview, frame) in zip(subviews, layout.frames) {
                subview.place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    proposal: ProposedViewSize(frame.size))
            }
        }

        /// Each subview's frame, in subview order, and the size they fill.
        private func frames(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
            let roles = subviews.map { $0[RoleKey.self] }
            let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
            let side = { (role: Role) in zip(roles, ideal).first { $0.0 == role }?.1 ?? .zero }
            let leading = side(.leading)
            let trailing = side(.trailing)
            let hasLeading = roles.contains(.leading)
            let textWidth =
                expanded
                ? width
                : max(0, width - leading.width - trailing.width - spacing * CGFloat(roles.count - 1))
            let text =
                zip(roles, subviews).first { $0.0 == .text }?.1
                .sizeThatFits(ProposedViewSize(width: textWidth, height: nil)) ?? .zero
            if expanded {
                let row = max(leading.height, trailing.height)
                let height = text.height + rowSpacing + row
                let frames = roles.map { role -> CGRect in
                    switch role {
                    case .text: CGRect(x: 0, y: 0, width: width, height: text.height)
                    case .leading:
                        CGRect(origin: CGPoint(x: 0, y: height - (row + leading.height) / 2), size: leading)
                    case .trailing:
                        CGRect(
                            origin: CGPoint(x: width - trailing.width, y: height - (row + trailing.height) / 2),
                            size: trailing)
                    }
                }
                return (frames, CGSize(width: width, height: height))
            }
            // One row, its parts on a shared bottom line.
            let height = max(leading.height, text.height, trailing.height)
            let textX = hasLeading ? leading.width + spacing : 0
            let frames = roles.map { role -> CGRect in
                switch role {
                case .leading: CGRect(origin: CGPoint(x: 0, y: height - leading.height), size: leading)
                case .text: CGRect(x: textX, y: height - text.height, width: textWidth, height: text.height)
                case .trailing:
                    CGRect(
                        origin: CGPoint(x: width - trailing.width, y: height - trailing.height), size: trailing)
                }
            }
            return (frames, CGSize(width: width, height: height))
        }
    }

    /// The chat's settings among the box's buttons while you type: how full the context is, and a
    /// gauge for the model and how hard it thinks, which opens the level picker.
    struct ComposerControls: View {
        let chat: ChatControls
        @Binding var pickingLevel: Bool
        @Environment(\.composerButtonSize) private var size

        var body: some View {
            let thread = chat.thread
            HStack(spacing: 2) {
                if let usage = thread.usage, let context = usage.context {
                    ContextMeter(thread: thread, usage: usage, context: context, compact: true)
                }
                if let model = thread.model {
                    Button {
                        pickingLevel.toggle()
                    } label: {
                        Image(systemName: Self.gauge(model.reasoning, reasons: thread.takesReasoning(model)))
                            .font(.system(size: size * 0.55))
                            .foregroundStyle(pickingLevel ? Theme.ink : Theme.ink.opacity(0.8))
                            .frame(width: size, height: size)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Model and thinking"))
                    .accessibilityValue(
                        Text("\(ModelControls.short(model.name)), \(ModelControls.levelName(model.reasoning))"))
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }

        /// A gauge whose needle rises with the thinking level; the middle for the provider's default.
        static func gauge(_ level: ReasoningLevel?, reasons: Bool) -> String {
            guard reasons, let level else {
                return reasons ? "gauge.with.dots.needle.50percent" : "gauge.with.dots.needle.0percent"
            }
            let percent =
                switch level {
                case .off: 0
                case .minimal, .low: 33
                case .medium: 50
                case .high, .xhigh: 67
                case .max, .ultra: 100
                }
            return "gauge.with.dots.needle.\(percent)percent"
        }
    }

    /// Opened by the gauge, above the message box while the keyboard stays up: the chat's model and
    /// level, which open the model sheet, over a slider of thinking levels.
    struct LevelPanel: View {
        let chat: ChatControls
        let openModels: () -> Void

        var body: some View {
            if let model = chat.thread.model {
                VStack(spacing: 14) {
                    Button(action: openModels) {
                        HStack(spacing: 6) {
                            Text(ModelControls.short(model.name)).fontWeight(.semibold)
                            if chat.thread.takesReasoning(model) {
                                Text(ModelControls.levelName(model.reasoning)).foregroundStyle(Theme.secondaryInk)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        }
                        .font(.system(size: 17))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows the model and thinking settings"))
                    if chat.thread.takesReasoning(model) {
                        LevelSlider(level: model.reasoning) { chat.thread.setReasoning($0) }
                    } else {
                        Text("This model doesn't take a thinking level.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .floatingSurface(in: RoundedRectangle(cornerRadius: 28))
            }
        }
    }

    /// The thinking levels as stops on a track, from off on the left to the most on the right.
    /// Tap a stop or slide to it; the level changes when you let go.
    private struct LevelSlider: View {
        let level: ReasoningLevel?
        let set: (ReasoningLevel) -> Void
        /// The stop under your finger while you slide.
        @State private var dragging: Int?

        private let levels = ReasoningLevel.allCases
        private let height: CGFloat = 52
        private let knob: CGFloat = 44

        var body: some View {
            GeometryReader { geometry in
                let step = (geometry.size.width - height) / CGFloat(levels.count - 1)
                let x = { (index: Int) in height / 2 + CGFloat(index) * step }
                let selected = dragging ?? level.flatMap { levels.firstIndex(of: $0) }
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.selection)
                    if let selected {
                        Capsule()
                            .fill(Theme.primary)
                            .frame(width: x(selected) + height / 2)
                    }
                    ForEach(levels.indices, id: \.self) { index in
                        Circle()
                            .fill(
                                selected.map { index < $0 } == true
                                    ? Theme.primaryInk.opacity(0.3) : Theme.ink.opacity(0.3)
                            )
                            .frame(width: 8, height: 8)
                            .position(x: x(index), y: height / 2)
                    }
                    if let selected {
                        Circle()
                            .fill(Theme.primary)
                            .overlay(Circle().strokeBorder(Theme.primaryInk.opacity(0.1)))
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                            .frame(width: knob, height: knob)
                            .position(x: x(selected), y: height / 2)
                    }
                }
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in dragging = nearest(value.location.x, step: step) }
                        .onEnded { value in
                            let index = nearest(value.location.x, step: step)
                            dragging = nil
                            if levels[index] != level { set(levels[index]) }
                        }
                )
                .animation(.snappy(duration: 0.18), value: selected)
                .sensoryFeedback(.selection, trigger: selected)
            }
            .frame(height: height)
            .accessibilityElement()
            .accessibilityLabel(Text("Thinking"))
            .accessibilityValue(Text(ModelControls.levelName(level)))
            .accessibilityAdjustableAction { direction in
                let current = level.flatMap { levels.firstIndex(of: $0) } ?? levels.count / 2
                switch direction {
                case .increment where current + 1 < levels.count: set(levels[current + 1])
                case .decrement where current > 0: set(levels[current - 1])
                default: break
                }
            }
        }

        private func nearest(_ x: CGFloat, step: CGFloat) -> Int {
            min(levels.count - 1, max(0, Int(((x - height / 2) / step).rounded())))
        }
    }

    /// The model and thinking settings in full, opened from the level panel: the gateway's models
    /// and every level, each with Make Default.
    struct ModelSheet: View {
        let chat: ChatControls
        @State private var picking = ModelPicking()
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            let thread = chat.thread
            NavigationStack {
                Form {
                    if let model = thread.model {
                        Section {
                            row("Model", value: ModelControls.short(model.name)) {
                                ModelMenu(
                                    thread: thread, agentName: chat.agentName, agentDefault: chat.agentDefault,
                                    picking: picking)
                            }
                            if thread.takesReasoning(model) {
                                row("Thinking", value: ModelControls.levelName(model.reasoning)) {
                                    LevelMenu(thread: thread, agentName: chat.agentName)
                                }
                            }
                        } footer: {
                            Text(
                                "Changes apply to this chat. Make Default in each menu saves them for \(chat.agentName)."
                            )
                        }
                    }
                }
                .navigationTitle("Model and thinking")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .modelPickingAlerts(picking, thread: thread)
        }

        /// A setting with its value on the right, which opens its menu.
        private func row(_ title: LocalizedStringKey, value: String, @ViewBuilder menu: () -> some View) -> some View {
            LabeledContent(title) {
                Menu(content: menu) {
                    HStack(spacing: 4) {
                        Text(value).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        }
    }
#endif
