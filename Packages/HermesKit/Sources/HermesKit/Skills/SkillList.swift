import Foundation
import Observation

/// A skill an agent can load: from the hub, bundled with Hermes, mounted from elsewhere, or one
/// the agent wrote itself.
public struct Skill: Identifiable, Equatable, Sendable, Decodable {
    public let name: String
    public let description: String
    public let category: String?
    public var enabled: Bool
    /// How often the agent has used it lately.
    public let usage: Int?
    /// `hub`, `bundled`, `external` or `agent`.
    public let provenance: String?

    public var id: String { name }

    public init(
        name: String, description: String, category: String? = nil, enabled: Bool = true, usage: Int? = nil,
        provenance: String? = nil
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.enabled = enabled
        self.usage = usage
        self.provenance = provenance
    }
}

/// One agent's skills, from the dashboard's skills routes, each switched on or off there.
@MainActor
@Observable
public final class SkillList {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    public let profile: String
    public private(set) var skills: [Skill] = []
    public private(set) var phase: Phase = .loading
    /// The last switch that didn't go through, shown under the list.
    public private(set) var problem: String?

    private let auth: @MainActor () -> AuthSession?
    private var refreshing = false

    init(profile: String, auth: @escaping @MainActor () -> AuthSession?) {
        self.profile = profile
        self.auth = auth
    }

    /// Reloads the list, most used first. Keeps showing the old one if the reload fails.
    public func refresh() async {
        guard !refreshing, let auth = auth() else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let loaded = try await auth.json([Skill].self, path: "/api/skills?profile=\(escaped)")
            skills = loaded.sorted { ($0.usage ?? 0, $1.name) > ($1.usage ?? 0, $0.name) }
            phase = .ready
        } catch {
            if phase != .ready { phase = .failed(AppModel.describe(error)) }
        }
    }

    /// Turns a skill on or off. The switch moves at once and moves back if the gateway refuses.
    public func setEnabled(_ enabled: Bool, for skill: Skill) {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }), let auth = auth() else { return }
        problem = nil
        skills[index].enabled = enabled
        struct Toggle: Encodable, Sendable {
            let name: String
            let enabled: Bool
            let profile: String
        }
        struct Reply: Decodable, Sendable {}
        Task {
            do {
                _ = try await auth.json(
                    Reply.self, path: "/api/skills/toggle?profile=\(escaped)", method: "PUT",
                    body: Toggle(name: skill.name, enabled: enabled, profile: profile))
            } catch {
                if let current = skills.firstIndex(where: { $0.id == skill.id }) { skills[current].enabled = !enabled }
                problem =
                    enabled
                    ? String(localized: "Couldn't turn on “\(skill.name)”: \(AppModel.describe(error))")
                    : String(localized: "Couldn't turn off “\(skill.name)”: \(AppModel.describe(error))")
            }
        }
    }

    private var escaped: String {
        profile.addingPercentEncoding(withAllowedCharacters: .urlUnreservedCharacters) ?? profile
    }

    #if DEBUG
        /// Tests and previews: a list already showing `skills`.
        public static func sample(_ skills: [Skill]) -> SkillList {
            let list = SkillList(profile: "sample", auth: { nil })
            list.skills = skills
            list.phase = .ready
            return list
        }
    #endif
}
