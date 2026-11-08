import HermesKit
import SwiftUI

/// How a chat's model and thinking level read in its menus.
enum ModelControls {
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

#if os(macOS)
    /// The chat's model, how hard it thinks and how full its context is, as menus in the agent's
    /// panel on the Mac: the gateway's models (this provider's first, others in submenus), the
    /// thinking levels for models that take one, and the context's numbers with Compress. A model
    /// or level pick changes this chat only; Make Default saves it as the agent's own. Moved here
    /// from under the message box (November 2026), which keeps nothing under it now.
    struct ChatModelSection: View {
        let thread: ChatThread
        let agentName: String
        /// The agent's default model, as the roster reports it.
        let agentDefault: AgentDetails?
        @State private var picking = ModelPicking()

        var body: some View {
            if let model = thread.model {
                Section {
                    LabeledContent("Model") {
                        Menu {
                            ModelMenu(
                                thread: thread, agentName: agentName, agentDefault: agentDefault, picking: picking)
                        } label: {
                            Text(ModelControls.short(model.name)).lineLimit(1)
                        }
                        .fixedSize()
                        .clickable()
                        .help("Model for this chat")
                        .accessibilityLabel(Text("Model: \(ModelControls.short(model.name))"))
                    }
                    if thread.takesReasoning(model) {
                        LabeledContent("Thinking") {
                            Menu {
                                LevelMenu(thread: thread, agentName: agentName)
                            } label: {
                                Text(ModelControls.levelName(model.reasoning)).lineLimit(1)
                            }
                            .fixedSize()
                            .clickable()
                            .help("How hard the Bot thinks in this chat")
                            .accessibilityLabel(Text("Thinking: \(thinking(model))"))
                        }
                    }
                    if let usage = thread.usage, let context = usage.context {
                        LabeledContent("Context") {
                            ContextMeter(thread: thread, usage: usage, context: context)
                        }
                    }
                } header: {
                    ProfileSectionHeader("This Chat")
                }
                .modelPickingAlerts(picking, thread: thread)
            }
        }

        private func thinking(_ model: ChatModel) -> String {
            model.reasoning.map(ModelControls.name(of:)) ?? String(localized: "Default")
        }
    }
#endif

/// Switching a chat's model or saving it as the agent's default can need a yes first (an
/// expensive model) or fail. The Mac panel's menus and the iPhone's model sheet ask and report here.
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

/// How full the chat's context is: on the Mac a menu in the agent's panel, beside the model and
/// thinking; on iPhone a ring among the message box's controls. Its menu gives the numbers and
/// compresses the conversation when it's getting full.
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
                // The number keeps a part-filled ring from reading as a spinner. In glass, like the
                // box's round buttons.
                HStack(spacing: 5) {
                    ring(size: 16, lineWidth: 2)
                    Text("\(context.percent)%")
                }
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 2)
                .frame(height: buttonSize - ComposerGlass.inset * 2)
            } else {
                // Plain text, like the model and thinking menus above it: a menu's label drops images.
                if thread.isCompressing {
                    Text("Compressing…")
                } else {
                    Text("\(approx)\(context.percent)% full").lineLimit(1)
                }
            }
        }
        .modifier(MeterStyle(compact: compact))
        #if os(macOS)
            .fixedSize()
        #endif
        .clickable()
        .help("How full this chat's context is")
        .accessibilityLabel(Text("Context \(context.percent) percent full"))
    }

    /// iPhone's sits among the message box's glass buttons; the Mac's is a menu like its neighbours.
    private struct MeterStyle: ViewModifier {
        let compact: Bool

        func body(content: Content) -> some View {
            if compact {
                content.menuStyle(.button).buttonStyle(.glass).buttonBorderShape(.capsule)
            } else {
                content
            }
        }
    }

    @ViewBuilder private func ring(size: CGFloat, lineWidth: CGFloat) -> some View {
        if thread.isCompressing {
            ProgressView().controlSize(.mini).frame(width: size, height: size)
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
        return Theme.ink.opacity(0.8)
    }
}
