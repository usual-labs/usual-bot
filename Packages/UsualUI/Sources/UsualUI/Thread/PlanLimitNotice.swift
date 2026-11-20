import HermesKit
import SwiftUI

/// A strip above the message box when the subscription a chat or room runs on is near a limit
/// (90% and up), or past it. The ✕ hides a warning until the next band (95%) or the limit
/// resets; a used-up limit stays, since replies won't come until then. The message box stays
/// usable: Hermes's numbers can be minutes old, and a fallback model may still answer.
struct PlanLimitNotice: View {
    let warning: PlanLimitWarning
    let text: String
    @AppStorage("dismissedPlanLimits") private var dismissed = ""

    var body: some View {
        if !isDismissed {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: warning.limit.isUsedUp ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .zoomedFont(size: 12)
                    .foregroundStyle(warning.limit.isUsedUp ? Theme.danger : Theme.needsYouInk)
                    .accessibilityHidden(true)
                Text(text)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !warning.limit.isUsedUp {
                    Button {
                        dismissed = Self.adding(warning.dismissKey, to: dismissed)
                    } label: {
                        Image(systemName: "xmark")
                            .zoomedFont(size: 10, weight: .semibold)
                            .zoomedFrame(width: 22, height: 22)
                            .contentShape(Rectangle())
                            .touchTarget(width: 22, height: 22)
                    }
                    .buttonStyle(.clickable(.borderless))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Hide this warning"))
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var isDismissed: Bool {
        !warning.limit.isUsedUp && dismissed.split(separator: "\n").contains { $0 == warning.dismissKey }
    }

    /// The newest keys only: a key stops mattering once its limit resets.
    static func adding(_ key: String, to list: String) -> String {
        (list.split(separator: "\n").map(String.init).suffix(19) + [key]).joined(separator: "\n")
    }
}

extension PlanLimitWarning {
    /// "You've used 91% of Anthropic's weekly limit. It resets Mon 07:59."
    func chatText(agentName: String, now: Date = .now) -> String {
        let limit = "\(provider)'s \(self.limit.name)"
        guard self.limit.isUsedUp else {
            let percent = min(99, Int(self.limit.usedPercent))
            guard let reset = resetText(now: now) else {
                return String(localized: "You've used \(percent)% of \(limit) limit.")
            }
            return String(localized: "You've used \(percent)% of \(limit) limit. It resets \(reset).")
        }
        guard let reset = resetText(now: now) else {
            return String(
                localized: "\(limit) limit is used up. Switch \(agentName) to another model to keep going.")
        }
        return String(
            localized:
                "\(limit) limit is used up. \(agentName) can reply again \(reset), or you can switch it to another model."
        )
    }

    /// "You've used 91% of Anthropic's weekly limit, which Forge and Atlas run on. It resets Mon 07:59."
    func roomText(members: [String], now: Date = .now) -> String {
        let limit = "\(provider)'s \(self.limit.name)"
        let names = members.formatted(.list(type: .and))
        let reset = resetText(now: now)
        guard self.limit.isUsedUp else {
            let percent = min(99, Int(self.limit.usedPercent))
            let used =
                members.count == 1
                ? String(localized: "You've used \(percent)% of \(limit) limit, which \(names) runs on.")
                : String(localized: "You've used \(percent)% of \(limit) limit, which \(names) run on.")
            guard let reset else { return used }
            return used + " " + String(localized: "It resets \(reset).")
        }
        guard let reset else {
            return String(localized: "\(limit) limit is used up, so \(names) can't reply.")
        }
        return String(localized: "\(limit) limit is used up, so \(names) can't reply until \(reset).")
    }

    /// "at 15:59" today, "Mon 07:59" after.
    private func resetText(now: Date) -> String? {
        guard let resetsAt = limit.resetsAt, resetsAt > now else { return nil }
        let time = resetsAt.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(resetsAt, inSameDayAs: now) { return String(localized: "at \(time)") }
        return resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
