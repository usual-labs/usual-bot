import HermesKit
import SwiftUI

/// The chat's model as a glass button in the profile, opening a list to pick from: the chat's
/// provider first, the others folded, a search over all of them, and Make Default at the foot.
/// A popover with plain rows, not a menu: an inline picker nested in a menu section drew only the
/// provider's name on the Mac, with no models under it to pick (November 2026).
struct ModelButton: View {
    let thread: ChatThread
    let model: ChatModel
    let agentName: String
    let agentDefault: AgentDetails?
    let picking: ModelPicking
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: 4) {
                Text(ModelControls.short(model.name)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.clickable(.glass))
        .controlSize(.small)
        .fixedSize()
        .help("Model for this chat")
        .accessibilityLabel(Text("Model: \(ModelControls.short(model.name))"))
        .accessibilityHint(Text("Shows the models you can switch this chat to"))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ModelList(
                thread: thread, agentName: agentName, agentDefault: agentDefault, picking: picking
            ) { isOpen = false }
            #if os(iOS)
                .presentationDetents([.medium, .large])
            #endif
        }
    }
}

/// What the model popover lists: the chat's provider first, then the others, each narrowed by the
/// search. Kept apart from the view so it can be tested.
enum ModelChoices {
    struct Group: Equatable, Identifiable {
        let provider: ModelProvider
        let models: [String]
        var id: String { provider.slug }
    }

    static func groups(_ providers: [ModelProvider], current: ChatModel, query: String) -> [Group] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let ordered =
            providers.filter { $0.slug == current.provider } + providers.filter { $0.slug != current.provider }
        return ordered.compactMap { provider in
            // The chat's model may sit outside an aggregator's shortlist.
            var names = provider.models
            if provider.slug == current.provider, !names.contains(current.name) { names.insert(current.name, at: 0) }
            let matching = names.filter { name in
                let haystack = "\(name) \(provider.name)".lowercased()
                return words.allSatisfy(haystack.contains)
            }
            return matching.isEmpty ? nil : Group(provider: provider, models: matching)
        }
    }
}

private struct ModelList: View {
    let thread: ChatThread
    let agentName: String
    let agentDefault: AgentDetails?
    let picking: ModelPicking
    let dismiss: () -> Void

    @State private var query = ""
    @State private var opened: Set<String> = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        if let model = thread.model {
            VStack(spacing: 0) {
                search
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let groups = ModelChoices.groups(thread.modelProviders, current: model, query: query)
                        if thread.modelProviders.isEmpty {
                            // The catalog hasn't arrived (or can't): the current model, at least.
                            row(model.name, provider: model.provider, current: model)
                        } else if groups.isEmpty {
                            Text("No models match “\(query)”.")
                                .foregroundStyle(Theme.secondaryInk)
                                .padding(10)
                        }
                        ForEach(groups) { group in
                            section(group, current: model)
                        }
                    }
                    .padding(6)
                }
                #if os(macOS)
                    .frame(maxHeight: 360)
                #endif
                Divider()
                footer(model)
            }
            #if os(macOS)
                .frame(width: 300)
                .fixedSize(horizontal: false, vertical: true)
            #else
                // A sheet on iPhone: its full width, and the list to the bottom.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)
            #endif
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryInk)
            // Hidden label: the popover inherits the profile form's style, which put the field
            // after its label and the placeholder at the trailing end.
            TextField("Search models", text: $query, prompt: Text("Search models"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .focused($searchFocused)
                .accessibilityLabel(Text("Search models"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.ink.opacity(0.06), in: Capsule())
        .padding(8)
        #if os(macOS)
            .onAppear { searchFocused = true }
        #endif
    }

    /// The chat's provider stays open; the others fold until opened, or while searching.
    @ViewBuilder private func section(_ group: ModelChoices.Group, current: ChatModel) -> some View {
        let isCurrent = group.provider.slug == current.provider
        let isOpen = isCurrent || !query.isEmpty || opened.contains(group.id)
        Button {
            if !isCurrent && query.isEmpty {
                if opened.contains(group.id) { opened.remove(group.id) } else { opened.insert(group.id) }
            }
        } label: {
            HStack {
                Text(group.provider.name)
                    .zoomedFont(size: 11, weight: .semibold)
                    .foregroundStyle(Theme.secondaryInk)
                    .textCase(.uppercase)
                Spacer()
                if !isCurrent && query.isEmpty {
                    Text("^[\(group.models.count) model](inflect: true)")
                        .zoomedFont(size: 11)
                        .foregroundStyle(Theme.secondaryInk)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.clickable)
        .disabled(isCurrent || !query.isEmpty)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(Text(isOpen ? "Open" : "Folded"))
        if isOpen {
            ForEach(group.models, id: \.self) { name in
                row(name, provider: group.provider.slug, current: current)
            }
        }
    }

    private func row(_ name: String, provider: String, current: ChatModel) -> some View {
        let selected = name == current.name && provider == current.provider
        return Button {
            dismiss()
            guard !selected else { return }
            Task { await picking.switchTo(name, provider: provider, in: thread) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .imageScale(.small)
                    .opacity(selected ? 1 : 0)
                Text(ModelControls.short(name)).lineLimit(1)
                Spacer(minLength: 8)
                if isAgentDefault(name, provider: provider) {
                    Text("\(agentName)'s default")
                        .zoomedFont(size: 11)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if selected { RoundedRectangle(cornerRadius: 7).fill(Theme.ink.opacity(0.08)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.clickable)
        .foregroundStyle(Theme.ink)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func footer(_ model: ChatModel) -> some View {
        HStack(spacing: 8) {
            Text("Changes this chat only")
                .zoomedFont(size: 11.5)
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if isAgentDefault(model.name, provider: model.provider) {
                Label("\(agentName)'s Default", systemImage: "checkmark.seal")
                    .zoomedFont(size: 11.5)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
            } else {
                Button("Make Default for \(agentName)") {
                    dismiss()
                    Task { await picking.makeDefault(in: thread) }
                }
                .buttonStyle(.clickable(.glass))
                .controlSize(.small)
                .lineLimit(1)
                .help("Use \(ModelControls.short(model.name)) in \(agentName)'s other chats, routines and rooms too")
            }
        }
        .padding(10)
    }

    /// Whether `name` is the model the roster lists as the agent's default.
    private func isAgentDefault(_ name: String, provider: String) -> Bool {
        guard let defaultName = agentDefault?.model else { return false }
        return defaultName == name && (agentDefault?.provider.map { $0 == provider } ?? true)
    }
}
