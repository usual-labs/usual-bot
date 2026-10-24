import HermesKit
import SwiftUI

/// The chat's model and how hard it thinks, as two small menus under the message box: the
/// gateway's models (this provider's first, others in submenus), and the thinking levels for
/// models that take one. A pick changes this chat only; the agent's default stays as it is.
struct ModelControls: View {
    let thread: ChatThread
    /// The gateway asked for a yes before switching (an expensive model).
    @State private var confirming: Pick?
    @State private var problem: String?

    /// The menus' row, centred between the box above and the window's bottom edge: `gap` on
    /// either side of it. Gap, row and gap add up to the box's 20 pt side margin (ThreadPane), so
    /// the box sits as far from the bottom as from the sides.
    static let height: CGFloat = 16
    static let gap: CGFloat = 2

    struct Pick: Equatable {
        let model: String
        let provider: String
        let message: String
    }

    var body: some View {
        if let model = thread.model {
            HStack(spacing: 2) {
                if let usage = thread.usage, let context = usage.context {
                    ContextMeter(thread: thread, usage: usage, context: context)
                }
                Menu {
                    models(model)
                } label: {
                    label(Self.short(model.name))
                }
                .help("Model for this chat")
                .accessibilityLabel(Text("Model: \(Self.short(model.name))"))
                if reasons(model) {
                    Menu {
                        levels(model)
                    } label: {
                        label(model.reasoning.map(Self.name(of:)) ?? String(localized: "Default thinking"))
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
            .task(id: thread.isAttached) {
                guard thread.isAttached else { return }
                async let models: Void = thread.loadModels()
                async let usage: Void = thread.loadUsage()
                _ = await (models, usage)
            }
            .alert(
                "Switch to \(confirming.map { Self.short($0.model) } ?? "")?",
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                presenting: confirming
            ) { pick in
                Button("Switch") { Task { await switchTo(pick.model, provider: pick.provider, confirmed: true) } }
                Button("Keep \(Self.short(model.name))", role: .cancel) {}
            } message: { pick in
                Text(pick.message)
            }
            .alert(
                "Couldn't switch models",
                isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
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

    @ViewBuilder private func models(_ model: ChatModel) -> some View {
        let providers = thread.modelProviders
        if let current = providers.first(where: { $0.slug == model.provider }) {
            Section(current.name) { picker(current, model) }
        } else if providers.isEmpty {
            // The catalog hasn't arrived (or can't): the current model, at least.
            Section(model.provider) {
                Button(Self.short(model.name), systemImage: "checkmark") {}.disabled(true)
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
    }

    private func levels(_ model: ChatModel) -> some View {
        Picker(
            "Thinking",
            selection: Binding(get: { model.reasoning }, set: { level in if let level { thread.setReasoning(level) } })
        ) {
            ForEach(ReasoningLevel.allCases, id: \.self) { level in
                Text(Self.name(of: level)).tag(Optional(level))
            }
        }
        .pickerStyle(.inline)
    }

    /// One provider's models, the chat's own ticked.
    private func picker(_ provider: ModelProvider, _ model: ChatModel) -> some View {
        Picker(
            provider.name,
            selection: Binding(
                get: { provider.slug == model.provider ? model.name : "" },
                set: { name in Task { await switchTo(name, provider: provider.slug) } })
        ) {
            // The chat's model may sit outside an aggregator's shortlist.
            let names = provider.slug == model.provider && !provider.models.contains(model.name)
                ? [model.name] + provider.models : provider.models
            ForEach(names, id: \.self) { name in Text(Self.short(name)).tag(name) }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func switchTo(_ name: String, provider: String, confirmed: Bool = false) async {
        switch await thread.setModel(name, provider: provider, confirmed: confirmed) {
        case .switched, .next: break
        case .needsConfirmation(let message): confirming = Pick(model: name, provider: provider, message: message)
        case .failed(let message): problem = message
        }
    }

    /// Whether the chat's model takes a thinking level; assumed when the catalog doesn't say.
    private func reasons(_ model: ChatModel) -> Bool {
        thread.modelProviders.first { $0.slug == model.provider }?.reasons(model.name) ?? true
    }

    /// A model ID without its vendor folder: `x-ai/grok-5` reads `grok-5`.
    static func short(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
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

/// How full the chat's context is, as a small ring and percentage beside the model menu; its menu
/// gives the numbers and compresses the conversation when it's getting full.
private struct ContextMeter: View {
    let thread: ChatThread
    let usage: ChatUsage
    let context: ChatUsage.Context

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
            HStack(spacing: 4) {
                if thread.isCompressing {
                    ProgressView().controlSize(.mini)
                } else {
                    ZStack {
                        Circle().stroke(Theme.secondaryInk.opacity(0.25), lineWidth: 1.5)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(context.percent, 100)) / 100)
                            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 9, height: 9)
                }
                Text("\(context.percent)%")
            }
            .font(.system(size: 10, weight: .light))
            .foregroundStyle(Theme.secondaryInk.opacity(0.7))
            .padding(.horizontal, 6)
            .frame(height: ModelControls.height)
            .contentShape(Rectangle())
        }
        .help("How full this chat's context is")
        .accessibilityLabel(Text("Context \(context.percent) percent full"))
    }

    /// Hermes's own count rather than the provider's.
    private var approx: String { context.estimated ? "~" : "" }

    /// Amber once the context is mostly full, when compressing starts to matter.
    private var tint: Color { context.percent >= 80 ? Theme.needsYouInk : Theme.secondaryInk.opacity(0.7) }
}

