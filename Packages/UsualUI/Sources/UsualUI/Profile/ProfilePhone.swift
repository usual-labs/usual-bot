#if os(iOS)
    import HermesKit
    import SwiftUI

    // The iPhone profile's pieces, laid out like a contact's info page rather than the Mac panel:
    // the Bot centred at the top, its description in a card, this chat's settings as Settings rows
    // with menus, and Hide and Delete at the end.

    /// A row's icon on iPhone: a white symbol on a coloured rounded square, as in Settings.
    struct ProfileRowIcon: View {
        let systemName: String
        let color: Color
        @ScaledMetric(relativeTo: .body) private var size: CGFloat = 29

        var body: some View {
            Image(systemName: systemName)
                .font(.system(size: size * 0.55, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// A Settings row's label: the coloured icon and its name.
    struct ProfileRowLabel: View {
        let title: LocalizedStringKey
        let systemName: String
        let color: Color

        var body: some View {
            Label {
                Text(title).foregroundStyle(Theme.ink)
            } icon: {
                ProfileRowIcon(systemName: systemName, color: color)
            }
        }
    }

    /// What the Bot does, in a card under its name: three lines until you tap it.
    struct ProfileAbout: View {
        let description: String
        @State private var isWhole = false

        /// About where three lines run out on the narrowest iPhone.
        private static let long = 120

        var body: some View {
            let canExpand = description.count > Self.long
            VStack(alignment: .leading, spacing: 3) {
                Text("About")
                    .zoomedFont(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                Text(description)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(isWhole ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if canExpand {
                    Text(isWhole ? "Less" : "More")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canExpand else { return }
                withAnimation(.snappy) { isWhole.toggle() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("About: \(description)"))
            .accessibilityAddTraits(canExpand ? .isButton : [])
            .accessibilityHint(canExpand ? Text(isWhole ? "Shows less" : "Shows all of it") : Text(""))
        }
    }

    /// This chat's model, thinking and context as Settings rows. The model opens the model list;
    /// thinking is a menu of the levels with Make Default under them; the context opens its page.
    struct PhoneChatSection: View {
        let thread: ChatThread
        let agentName: String
        let agentDefault: AgentDetails?
        @State private var picking = ModelPicking()

        var body: some View {
            if let model = thread.model {
                Section {
                    ModelButton(
                        thread: thread, model: model, agentName: agentName, agentDefault: agentDefault,
                        picking: picking, asRow: true)
                    if thread.takesReasoning(model) {
                        thinking(model)
                    }
                    if let usage = thread.usage, let context = usage.context {
                        NavigationLink {
                            ContextPage(thread: thread)
                                .navigationTitle("Context")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            LabeledContent {
                                HStack(spacing: 8) {
                                    Text("\(approx(context))\(context.percent)% used")
                                        .foregroundStyle(
                                            ContextGauge.isFilling(context) ? Theme.needsYouInk : Theme.secondaryInk)
                                    ContextRing(context: context)
                                }
                            } label: {
                                ProfileRowLabel(
                                    title: "Context", systemName: "gauge.with.dots.needle.33percent", color: .gray)
                            }
                        }
                        .accessibilityValue(Text("\(context.percent) percent full"))
                    }
                } header: {
                    ProfileSectionHeader("This Chat")
                }
                .modelPickingAlerts(picking, thread: thread)
            }
        }

        private func thinking(_ model: ChatModel) -> some View {
            Menu {
                Picker("Thinking", selection: level(model)) {
                    ForEach(ReasoningLevel.allCases, id: \.self) { level in
                        Text(ModelControls.name(of: level)).tag(Optional(level))
                    }
                }
                if model.reasoning != nil {
                    Section {
                        Button("Make Default for \(agentName)", systemImage: "pin") {
                            Task { await thread.makeReasoningDefault() }
                        }
                    }
                }
            } label: {
                LabeledContent {
                    MenuValue(text: ModelControls.levelName(model.reasoning))
                } label: {
                    ProfileRowLabel(title: "Thinking", systemName: "brain", color: .purple)
                }
            }
            .accessibilityLabel(Text("Thinking"))
            .accessibilityValue(Text(ModelControls.levelName(model.reasoning)))
            .accessibilityHint(Text("How hard the Bot thinks in this chat"))
        }

        private func level(_ model: ChatModel) -> Binding<ReasoningLevel?> {
            Binding(
                get: { model.reasoning },
                set: { level in
                    if let level, level != model.reasoning { thread.setReasoning(level) }
                })
        }

        private func approx(_ context: ChatUsage.Context) -> String { context.estimated ? "~" : "" }
    }

    /// A menu row's value: grey, with the up-and-down chevrons a Settings pop-up shows.
    struct MenuValue: View {
        let text: String

        var body: some View {
            HStack(spacing: 4) {
                Text(text).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .foregroundStyle(Theme.secondaryInk)
        }
    }

    /// How full the context is, as a small ring beside the percentage.
    private struct ContextRing: View {
        let context: ChatUsage.Context
        @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20

        var body: some View {
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(max(CGFloat(context.percent) / 100, 0), 1))
                    .stroke(
                        ContextGauge.isFilling(context) ? Theme.needsYouInk : Theme.secondaryInk,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    /// The chat's context with room for it: how much is used of the model's window, the totals so
    /// far, and Compress with what it does.
    struct ContextPage: View {
        let thread: ChatThread

        var body: some View {
            List {
                if let usage = thread.usage, let context = usage.context {
                    let filling = ContextGauge.isFilling(context)
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(approx(context))\(ChatThread.tokens(context.used))")
                                    .font(.largeTitle.bold())
                                    .monospacedDigit()
                                Text("of \(ChatThread.tokens(context.max)) tokens")
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                            .accessibilityElement(children: .combine)
                            ProgressView(value: min(max(Double(context.percent) / 100, 0), 1))
                                .tint(filling ? Theme.needsYouInk : Theme.ink)
                                .accessibilityLabel(Text("Context"))
                                .accessibilityValue(Text("\(context.percent) percent full"))
                            Text(window(context))
                                .zoomedFont(.subheadline)
                                .foregroundStyle(filling ? Theme.needsYouInk : Theme.secondaryInk)
                        }
                        .padding(.vertical, 6)
                    }
                    Section {
                        LabeledContent("Sent to the model", value: ChatThread.tokens(usage.input))
                        LabeledContent("Written by the model", value: ChatThread.tokens(usage.output))
                        LabeledContent("Calls", value: usage.calls.formatted())
                        if usage.compressions > 0 {
                            LabeledContent("Compressed") { Text("^[\(usage.compressions) time](inflect: true)") }
                        }
                    } header: {
                        ProfileSectionHeader("This Chat So Far")
                    }
                    .monospacedDigit()
                    Section {
                        if thread.isCompressing {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Compressing… summarizing older messages.")
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                        } else {
                            Button("Compress Chat") { Task { await thread.compress() } }
                                .disabled(!thread.canCompress)
                                .tint(filling ? Theme.needsYouInk : nil)
                        }
                    } footer: {
                        Text(compressFooter(filling: filling))
                    }
                } else {
                    Text("The gateway hasn't said how full this chat is yet.")
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            .listStyle(.insetGrouped)
            .task { await thread.loadUsage() }
        }

        private func window(_ context: ChatUsage.Context) -> String {
            let model = thread.model.map { ModelControls.short($0.name) }
            if let model {
                return String(localized: "\(approx(context))\(context.percent)% of \(model)'s window")
            }
            return String(localized: "\(approx(context))\(context.percent)% full")
        }

        private func compressFooter(filling: Bool) -> String {
            if !thread.canCompress, !thread.isCompressing, thread.canSend {
                return String(localized: "Compress works between replies. Try again when the Bot has finished.")
            }
            let what = String(
                localized:
                    "Hermes summarizes older messages so the Bot has room again. You still see them here."
            )
            return filling ? String(localized: "The context is filling up. \(what)") : what
        }

        private func approx(_ context: ChatUsage.Context) -> String { context.estimated ? "~" : "" }
    }
#endif
