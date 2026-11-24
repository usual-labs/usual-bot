import Foundation

/// One of a subscription's usage limits, as the gateway reports it with the model catalog
/// (`model.options`, `providers[].usage.windows`): Claude's 5-hour and weekly limits, say. Hermes
/// asks the provider for them and keeps them a while, so they can be a few minutes old; it leaves
/// them out when it has none, as with an API key, which has no such limits.
public struct PlanLimit: Identifiable, Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        /// Running out stops every model on the login.
        case account
        /// It caps one model family ("Opus week"); other models keep working.
        case model
    }

    /// Hermes's name for it: "Current session", "Current week", "Opus week".
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let scope: Scope

    public var id: String { label }

    public init(label: String, usedPercent: Double, resetsAt: Date? = nil, scope: Scope = .account) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.scope = scope
    }

    init?(_ json: JSONValue) {
        guard let label = json["label"]?.stringValue?.nonBlank, case .number(let used) = json["used_percent"]
        else { return nil }
        self.label = label
        usedPercent = used
        resetsAt = json["resets_at"]?.stringValue.flatMap(Self.date)
        scope = json["scope"]?.stringValue == "model" ? .model : .account
    }

    /// The limits in a provider row; none when the gateway has no numbers for it.
    static func all(in row: JSONValue) -> [PlanLimit] {
        guard case .array(let windows) = row["usage"]?["windows"] else { return [] }
        return windows.compactMap(PlanLimit.init)
    }

    public var isUsedUp: Bool { usedPercent >= 100 }

    /// Whether this limit stops `model`: an account limit stops every model, a model limit only
    /// the family it names ("Opus week" stops `claude-opus-5-5`).
    public func applies(to model: String?) -> Bool {
        guard scope == .model else { return true }
        guard let model, let family = label.split(separator: " ").first?.lowercased() else { return false }
        return model.lowercased().contains(family)
    }

    /// The limit in a sentence: "5-hour", "weekly", "weekly Opus". Hermes's own label otherwise.
    public var name: String {
        switch label {
        case "Current session": return String(localized: "5-hour")
        case "Current week": return String(localized: "weekly")
        default:
            if label.hasSuffix(" week") {
                return String(localized: "weekly \(String(label.dropLast(" week".count)))")
            }
            return label.lowercased()
        }
    }

    /// From how full a limit is, the app warns: at 90%, again at 95%, and when it's used up.
    static let warningBands: [Double] = [90, 95, 100]

    /// The highest warning band this limit has reached, if any.
    var band: Double? { Self.warningBands.last { usedPercent >= $0 } }

    /// Hermes writes Python's `isoformat()`, whose fraction of a second can have six digits, which
    /// `ISO8601DateFormatter` refuses. A reset time needs no fraction.
    static func date(_ text: String) -> Date? {
        let whole = text.replacing(/\.\d+/, with: "")
        return try? Date(whole, strategy: .iso8601)
    }
}

/// A limit worth warning about for one provider: the fullest one at 90% or more.
public struct PlanLimitWarning: Equatable, Sendable {
    /// The provider's name, as the gateway's catalog gives it ("Anthropic").
    public let provider: String
    public let limit: PlanLimit
    /// Dismissing hides this warning until the next band or the limit resets.
    public let dismissKey: String

    /// The fullest limit in `limits` that stops `model` and has reached a warning band.
    public init?(provider: ModelProvider, model: String?) {
        let reached = provider.limits.filter { $0.applies(to: model) && $0.band != nil }
        guard let limit = reached.max(by: { $0.usedPercent < $1.usedPercent }), let band = limit.band else {
            return nil
        }
        self.provider = provider.name
        self.limit = limit
        let reset = limit.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        dismissKey = "\(provider.slug)|\(limit.label)|\(Int(band))|\(reset)"
    }
}
