import HermesKit
import SwiftUI

/// The chat's model and how hard it thinks, as two small menus under the message box on the Mac:
/// the gateway's models (this provider's first, others in submenus), and the thinking levels for
/// models that take one. A pick changes this chat only; Make Default saves it as the agent's own.
/// On iPhone the box shows the same choices as a gauge while you type (ComposerControls.swift).
struct ModelControls: View {
    let thread: ChatThread
    let agentName: String
    /// The agent's default model, as the roster reports it.
    let agentDefault: AgentDetails?
    @State private var picking = ModelPicking()

    /// The menus' row, centred between the box above and the window's bottom edge: `gap` on
    /// either side of it. Gap, row and gap add up to the box's 20 pt side margin (ThreadPane), so
    /// the box sits as far from the bottom as from the sides.
    static let height: CGFloat = 16
    static let gap: CGFloat = 2

    var body: some View {
        if let model = thread.model {
            HStack(spacing: 2) {
                if let usage = thread.usage, let context = usage.context {
                    ContextMeter(thread: thread, usage: usage, context: context)
                }
                Menu {
                    ModelMenu(thread: thread, agentName: agentName, agentDefault: agentDefault, picking: picking)
                } label: {
                    label(Self.short(model.name))
                }
                .help("Model for this chat")
                .accessibilityLabel(Text("Model: \(Self.short(model.name))"))
                if thread.takesReasoning(model) {
                    Menu {
                        LevelMenu(thread: thread, agentName: agentName)
                    } label: {
                        label(Self.levelName(model.reasoning))
                    }
                    .help("How hard the agent thinks in this chat")
                    .accessibilityLabel(
                        Text("Thinking: \(model.reasoning.map(Self.name(of:)) ?? String(localized: "Default"))"))
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .task(id: thread.isAttached) { await thread.loadModelsAndUsage() }
            .modelPickingAlerts(picking, thread: thread)
        }
    }

    /// Quiet text with a chevron, so the two read as settings of the box above.
    private func label(_ text: String) -> some View {
        HStack(spacing: 2) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 5))
        }
        .font(.system(size: 10, weight: .light))
        .foregroundStyle(Theme.secondaryInk.opacity(0.7))
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .contentShape(Rectangle())
    }

    /// A model ID without its vendor folder: `x-ai/grok-5` reads `grok-5`.
    static func short(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    /// The chat's thinking level, or the provider's default when none is set.
    static func levelName(_ level: ReasoningLevel?) -> String {
        level.map(name(of:)) ?? String(localized: "Default thinking")
    }

    static func name(of level: ReasoningLevel) -> String {
        switch level {
        case .off: String(localized: "Off")
        case .minimal: String(localized: "Minimal")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .xhigh: String(localized: "Extra high")
        case .max: String(localized: "Max")
        case .ultra: String(localized: "Ultra")
        }
    }
}

/// Switching a chat's model or saving it as the agent's default can need a yes first (an
/// expensive model) or fail. The Mac's menus and the iPhone's model sheet ask and report here.
@MainActor
@Observable
final class ModelPicking {
    struct Pick: Equatable {
        let model: String
        let provider: String
        let message: String
        /// Asked while making it the agent's default, not while switching this chat.
        var asDefault = false
    }

    /// The gateway asked for a yes before switching (an expensive model).
    var confirming: Pick?
    var problem: String?

    func switchTo(_ name: String, provider: String, in thread: ChatThread, confirmed: Bool = false) async {
        switch await thread.setModel(name, provider: provider, confirmed: confirmed) {
        case .switched, .next: break
        case .needsConfirmation(let message): confirming = Pick(model: name, provider: provider, message: message)
        case .failed(let message): problem = message
        }
    }

    func makeDefault(in thread: ChatThread, confirmed: Bool = false) async {
        switch await thread.makeModelDefault(confirmed: confirmed) {
        case .switched, .next: break
        case .needsConfirmation(let message):
            if let model = thread.model {
                confirming = Pick(model: model.name, provider: model.provider, message: message, asDefault: true)
            }
        case .failed(let message): problem = message
        }
    }
}

extension ChatThread {
    /// Whether `model` takes a thinking level; assumed when the catalog doesn't say.
    func takesReasoning(_ model: ChatModel) -> Bool {
        modelProviders.first { $0.slug == model.provider }?.reasons(model.name) ?? true
    }

    /// The model catalog and the context numbers, once the chat is live.
    func loadModelsAndUsage() async {
        guard isAttached else { return }
        async let models: Void = loadModels()
        async let usage: Void = loadUsage()
        _ = await (models, usage)
    }
}

extension View {
    /// The questions and problems `picking` raises, as alerts.
    func modelPickingAlerts(_ picking: ModelPicking, thread: ChatThread) -> some View {
        modifier(ModelPickingAlerts(picking: picking, thread: thread))
    }
}

private struct ModelPickingAlerts: ViewModifier {
    let picking: ModelPicking
    let thread: ChatThread

    func body(content: Content) -> some View {
        content
            .alert(
                picking.confirming?.asDefault == true
                    ? "Make \(picking.confirming.map { ModelControls.short($0.model) } ?? "") the default?"
                    : "Switch to \(picking.confirming.map { ModelControls.short($0.model) } ?? "")?",
                isPresented: Binding(get: { picking.confirming != nil }, set: { if !$0 { picking.confirming = nil } }),
                presenting: picking.confirming
            ) { pick in
                if pick.asDefault {
                    Button("Make Default") { Task { await picking.makeDefault(in: thread, confirmed: true) } }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("Switch") {
                        Task {
                            await picking.switchTo(pick.model, provider: pick.provider, in: thread, confirmed: true)
                        }
                    }
                    Button("Keep \(ModelControls.short(thread.model?.name ?? ""))", role: .cancel) {}
                }
            } message: { pick in
                Text(pick.message)
            }
            .alert(
                "Couldn't change the model",
                isPresented: Binding(get: { picking.problem != nil }, set: { if !$0 { picking.problem = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(picking.problem ?? "")
            }
    }
}

/// A menu's model choices: this provider's models first, the others' in submenus, then Make Default.
struct ModelMenu: View {
    let thread: ChatThread
    let agentName: String
    let agentDefault: AgentDetails?
    let picking: ModelPicking

    var body: some View {
        if let model = thread.model {
            let providers = thread.modelProviders
            if let current = providers.first(where: { $0.slug == model.provider }) {
                Section(current.name) { picker(current, model) }
            } else if providers.isEmpty {
                // The catalog hasn't arrived (or can't): the current model, at least.
                Section(model.provider) {
                    Button(ModelControls.short(model.name), systemImage: "checkmark") {}.disabled(true)
                }
            }
            let others = providers.filter { $0.slug != model.provider }
            if !others.isEmpty {
                Section {
                    ForEach(others) { provider in
                        Menu(provider.name) { picker(provider, model) }
                    }
                }
            }
            Section {
                if isAgentDefault(model) {
                    Label("\(agentName)'s Default", systemImage: "checkmark.seal").disabled(true)
                } else {
                    Button("Make Default for \(agentName)", systemImage: "pin") {
                        Task { await picking.makeDefault(in: thread) }
                    }
                }
            }
        }
    }

    /// Whether the chat runs on the model the roster lists as the agent's default.
    private func isAgentDefault(_ model: ChatModel) -> Bool {
        guard let name = agentDefault?.model else { return false }
        return name == model.name && (agentDefault?.provider.map { $0 == model.provider } ?? true)
    }

    /// One provider's models, the chat's own ticked.
    private func picker(_ provider: ModelProvider, _ model: ChatModel) -> some View {
        Picker(
            provider.name,
            selection: Binding(
                get: { provider.slug == model.provider ? model.name : "" },
                set: { name in Task { await picking.switchTo(name, provider: provider.slug, in: thread) } })
        ) {
            // The chat's model may sit outside an aggregator's shortlist.
            let names =
                provider.slug == model.provider && !provider.models.contains(model.name)
                ? [model.name] + provider.models : provider.models
            ForEach(names, id: \.self) { name in Text(ModelControls.short(name)).tag(name) }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

/// A menu's thinking levels, then Make Default.
struct LevelMenu: View {
    let thread: ChatThread
    let agentName: String

    var body: some View {
        if let model = thread.model {
            Picker(
                "Thinking",
                selection: Binding(
                    get: { model.reasoning }, set: { level in if let level { thread.setReasoning(level) } })
            ) {
                ForEach(ReasoningLevel.allCases, id: \.self) { level in
                    Text(ModelControls.name(of: level)).tag(Optional(level))
                }
            }
            .pickerStyle(.inline)
            Section {
                Button("Make Default for \(agentName)", systemImage: "pin") {
                    Task { await thread.makeReasoningDefault() }
                }
                .disabled(model.reasoning == nil)
            }
        }
    }
}

/// How full the chat's context is, as a small ring and percentage beside the model menu (on
/// iPhone, a ring among the message box's controls); its menu gives the numbers and compresses the
/// conversation when it's getting full.
struct ContextMeter: View {
    let thread: ChatThread
    let usage: ChatUsage
    let context: ChatUsage.Context
    /// iPhone: a larger ring and number, as tall as the box's buttons.
    var compact = false
    @Environment(\.composerButtonSize) private var buttonSize

    var body: some View {
        Menu {
            Section {
                Text(
                    "Context: \(approx)\(ChatThread.tokens(context.used)) of \(ChatThread.tokens(context.max)) tokens (\(approx)\(context.percent)%)"
                )
                Text(
                    "This chat: \(ChatThread.tokens(usage.input)) tokens in, \(ChatThread.tokens(usage.output)) out, ^[\(usage.calls) call](inflect: true)"
                )
                if usage.compressions > 0 {
                    Text("Compressed ^[\(usage.compressions) time](inflect: true)")
                }
            }
            Button("Compress Conversation", systemImage: "arrow.down.right.and.arrow.up.left") {
                Task { await thread.compress() }
            }
            .disabled(!thread.canCompress)
        } label: {
            if compact {
                // The number keeps a part-filled ring from reading as a spinner. A grey pill, like
                // the box's round buttons.
                HStack(spacing: 5) {
                    ring(size: 16, lineWidth: 2)
                    Text("\(context.percent)%")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .frame(height: buttonSize)
                .background(Theme.selection, in: Capsule())
                .contentShape(Capsule())
            } else {
                HStack(spacing: 4) {
                    ring(size: 9, lineWidth: 1.5)
                    Text("\(context.percent)%")
                }
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Theme.secondaryInk.opacity(0.7))
                .padding(.horizontal, 6)
                .frame(height: ModelControls.height)
                .contentShape(Rectangle())
            }
        }
        .help("How full this chat's context is")
        .accessibilityLabel(Text("Context \(context.percent) percent full"))
    }

    @ViewBuilder private func ring(size: CGFloat, lineWidth: CGFloat) -> some View {
        if thread.isCompressing {
            ProgressView().controlSize(.mini).frame(width: compact ? size : nil, height: compact ? size : nil)
        } else {
            ZStack {
                Circle().stroke(Theme.secondaryInk.opacity(0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(min(context.percent, 100)) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
        }
    }

    /// Hermes's own count rather than the provider's.
    private var approx: String { context.estimated ? "~" : "" }

    /// Amber once the context is mostly full, when compressing starts to matter.
    private var tint: Color {
        if context.percent >= 80 { return Theme.needsYouInk }
        return compact ? Theme.ink.opacity(0.8) : Theme.secondaryInk.opacity(0.7)
    }
}
