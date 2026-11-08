import HermesKit
import SwiftUI

/// Settings › Usage: where tokens went across Bots, over time and by Bot, as Hermes reports it.
/// A Bot opens its own numbers: pushed on iPhone, in place on the Mac, whose settings pane has no
/// navigation stack.
struct UsageSettings: View {
    let model: AppModel
    @State private var openBotID: Contact.ID?

    var body: some View {
        let usage = model.usage
        Form {
            #if os(macOS)
                if let openBotID {
                    Section {
                        Button("All Bots", systemImage: "chevron.left") { self.openBotID = nil }
                            .buttonStyle(.clickable(.borderless))
                    }
                    BotUsageSections(model: model, botID: openBotID)
                } else {
                    overview(usage)
                }
            #else
                overview(usage)
            #endif
        }
        .modifier(UsagePage(model: model))
    }

    @ViewBuilder private func overview(_ usage: UsageOverview) -> some View {
        PeriodSection(usage: usage)
        switch usage.phase {
        case .loading:
            Section {
                switch (model.session, model.link) {
                case (.signedIn, .online):
                    waiting(String(localized: "Loading usage…"))
                case (.signedIn, .connecting):
                    waiting(String(localized: "Connecting…"))
                case (.signedIn, .offline):
                    Text("You're offline. Usage loads when the gateway is back.").foregroundStyle(Theme.secondaryInk)
                default:
                    Text("You’re not connected to a gateway. Sign in from the main window.")
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
        case .unsupported:
            Section {
                Text("This gateway's Hermes doesn't report usage. Updating Hermes on the gateway adds it.")
                    .foregroundStyle(Theme.secondaryInk)
            }
        case .failed(let reason):
            Section {
                Text("Couldn't load usage: \(reason)").foregroundStyle(Theme.secondaryInk)
                Button("Try Again") { Task { await usage.refresh() } }
                    .disabled(!isOnline)
            }
        case .ready:
            if usage.bots.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No usage yet").font(.headline).foregroundStyle(Theme.ink)
                        Text("No Bot used any tokens in the last \(usage.period.rawValue) days.")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    notes(usage)
                }
            } else {
                ReportSections(report: usage.combined, period: usage.period, today: usage.today)
                bots(usage)
            }
        }
    }

    private func bots(_ usage: UsageOverview) -> some View {
        let total = usage.combined.totalTokens
        return Section {
            ForEach(usage.bots) { bot in
                #if os(macOS)
                    Button {
                        openBotID = bot.id
                    } label: {
                        BotUsageRow(bot: bot, total: total)
                    }
                    .buttonStyle(.clickable(.plain))
                #else
                    NavigationLink {
                        Form { BotUsageSections(model: model, botID: bot.id) }
                            .modifier(UsagePage(model: model))
                            .navigationTitle(bot.contact.name)
                    } label: {
                        BotUsageRow(bot: bot, total: total)
                    }
                #endif
            }
        } header: {
            Text("By Bot")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "A Bot's usage covers its chats, routines, helpers and any other apps it talks in. Room replies count toward the Bot that wrote them."
                )
                notes(usage)
            }
        }
    }

    /// What didn't load, and how fresh the numbers are when the gateway is away.
    @ViewBuilder private func notes(_ usage: UsageOverview) -> some View {
        ForEach(usage.problems, id: \.self) { Text($0) }
        if case .offline = model.link, let loadedAt = usage.loadedAt {
            Text("You're offline. These numbers are from \(loadedAt.formatted(date: .omitted, time: .shortened)).")
        }
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(Theme.secondaryInk)
        }
    }

    private var isOnline: Bool { model.link.isOnline }
}

/// Loads the period on screen whenever it changes or the gateway comes back, on every page that
/// shows one: on iPhone a pushed Bot page has its own picker while the list underneath waits.
private struct UsagePage: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        let usage = model.usage
        let online = model.link.isOnline
        content
            .formStyle(.grouped)
            .thinScroller()
            .environment(\.botPictures, model.pictures)
            .task(id: RefreshKey(period: usage.period, online: online)) {
                if online { await usage.refresh() }
            }
            #if os(iOS)
                .refreshable { await usage.refresh() }
            #endif
    }

    private struct RefreshKey: Equatable {
        let period: UsageOverview.Period
        let online: Bool
    }
}

extension AppModel.Link {
    fileprivate var isOnline: Bool {
        if case .online = self { return true }
        return false
    }
}

/// The period picker, with a spinner while a refresh runs over numbers already shown.
private struct PeriodSection: View {
    @Bindable var usage: UsageOverview

    var body: some View {
        Section {
            HStack {
                Picker("Period", selection: $usage.period) {
                    ForEach(UsageOverview.Period.allCases) { Text($0.title).tag($0) }
                }
                .clickable()
                .pickerStyle(.segmented)
                .labelsHidden()
                if usage.isRefreshing, usage.phase == .ready {
                    ProgressView().controlSize(.small).accessibilityLabel(Text("Refreshing"))
                }
            }
        }
    }
}

/// Totals, the chart and where the tokens went, for every Bot or one.
private struct ReportSections: View {
    let report: UsageReport
    let period: UsageOverview.Period
    let today: Date

    var body: some View {
        Section {
            UsageTotals(report: report)
            UsageChart(report: report, period: period, today: today)
        } footer: {
            Text(
                "Hermes files a conversation's tokens under the day it began, and leaves out one that began before this period."
            )
        }
        Section {
            UsageBreakdown(report: report)
        } header: {
            Text("Where the tokens went")
        } footer: {
            if !report.jobs.isEmpty {
                Text(
                    "The rest is background work Hermes does beside your chats with a side model. It isn't split by day, so the chart leaves it out."
                )
            }
        }
    }
}

/// One Bot's numbers for the period on screen.
private struct BotUsageSections: View {
    let model: AppModel
    let botID: Contact.ID

    var body: some View {
        let usage = model.usage
        #if os(macOS)
            Section {
                if let contact = model.contacts.first(where: { $0.id == botID }) {
                    HStack(spacing: 10) {
                        AgentAvatar(contact: contact.with(activity: .idle), size: 32)
                        Text(contact.name).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                    }
                }
            }
        #endif
        PeriodSection(usage: usage)
        if let bot = usage.bots.first(where: { $0.id == botID }) {
            ReportSections(report: bot.report, period: usage.period, today: usage.today)
        } else if usage.phase == .ready {
            Section { Text("No usage in the last \(usage.period.rawValue) days.").foregroundStyle(Theme.secondaryInk) }
        } else {
            Section { ProgressView().controlSize(.small) }
        }
    }
}

private struct BotUsageRow: View {
    let bot: UsageOverview.BotUsage
    let total: Int

    var body: some View {
        let share = UsageFormat.share(bot.report.totalTokens, of: total)
        HStack(spacing: 12) {
            AgentAvatar(contact: bot.contact.with(activity: .idle), size: 30)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bot.contact.name).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Group {
                        if let cost = bot.report.cost {
                            Text("\(UsageFormat.tokens(bot.report.totalTokens)) · \(UsageFormat.cost(cost.amount))")
                        } else {
                            Text(UsageFormat.tokens(bot.report.totalTokens))
                        }
                    }
                    .foregroundStyle(Theme.secondaryInk)
                    .monospacedDigit()
                }
                ShareBar(fraction: share, color: bot.contact.accent)
            }
            #if os(macOS)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryInk)
            #endif
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(UsageFormat.percent(share)) of all tokens"))
        .accessibilityHint(Text("Shows this Bot's usage"))
    }
}
