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

/// The chat's model, how hard it thinks and how full its context is, in the agent's profile on the
/// Mac and iPhone: the model as a glass button opening a list of the gateway's models, thinking as a
/// stepped slider, and the context as a bar with Compress. A model or level pick changes this chat
/// only; Make Default saves it as the agent's own.
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
                    ModelButton(
                        thread: thread, model: model, agentName: agentName, agentDefault: agentDefault,
                        picking: picking)
                }
                if thread.takesReasoning(model) {
                    ThinkingControl(thread: thread, model: model, agentName: agentName)
                }
                if let usage = thread.usage, let context = usage.context {
                    ContextGauge(thread: thread, usage: usage, context: context)
                }
            } header: {
                ProfileSectionHeader("This Chat")
            }
            .modelPickingAlerts(picking, thread: thread)
        }
    }
}

/// Switching a chat's model or saving it as the agent's default can need a yes first (an
/// expensive model) or fail. The profile's menus ask and report here.
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

    /// The model catalog, with its subscription limits, and the context numbers, once the chat is
    /// live.
    func loadModelsAndUsage() async {
        guard isAttached else { return }
        async let models: Void = loadModels()
        async let usage: Void = loadUsage()
        _ = await (models, usage)
        // Hermes fetches subscription limits in the background the first time it's asked.
        guard !hasPlanLimits else { return }
        try? await Task.sleep(for: .seconds(10))
        if !Task.isCancelled { await loadModels() }
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
