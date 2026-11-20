import HermesKit
import SwiftUI

/// Settings › Usage: how much of each subscription's limits is used, one section per login, when
/// the gateway reports any. Nothing shows for API keys, which have no such limits.
struct PlanLimitSections: View {
    let limits: PlanLimitOverview

    var body: some View {
        ForEach(limits.accounts) { account in
            Section {
                ForEach(account.provider.limits) { PlanLimitRow(limit: $0) }
            } header: {
                Text("\(account.provider.name) subscription")
            } footer: {
                Text(
                    "Used by \(account.bots.map(\.name).formatted(.list(type: .and))). The numbers come from \(account.provider.name) through your gateway, and can be a few minutes old."
                )
            }
        }
    }
}

private struct PlanLimitRow: View {
    let limit: PlanLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.label).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text(detail).scaledFont(size: 12).foregroundStyle(Theme.secondaryInk)
            }
            // Drawn rather than a ProgressView, which loses its colour while the window is inactive.
            Capsule()
                .fill(Theme.border)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(tint).frame(width: proxy.size.width * min(limit.usedPercent, 100) / 100)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let used = String(localized: "\(Int(limit.usedPercent.rounded()))% used")
        guard let resetsAt = limit.resetsAt, resetsAt > .now else { return used }
        let reset = resetsAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return String(localized: "\(used) · resets \(reset)")
    }

    private var tint: Color {
        if limit.isUsedUp { return Theme.danger }
        return limit.usedPercent >= 90 ? Theme.needsYouInk : Theme.primary
    }
}
