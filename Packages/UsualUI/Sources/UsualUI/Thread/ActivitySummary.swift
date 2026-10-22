import Foundation
import HermesKit

/// Words for a run of tool calls: "Hermes read 2 files, edited 1 and ran 3 commands · 48s".
enum ActivitySummary {
    enum Category: CaseIterable {
        case read, edit, run, search, web, other
    }

    static func category(of tool: String) -> Category {
        switch tool {
        case "read_file", "read_terminal", "skill_view", "skills_list": return .read
        case "write_file", "patch": return .edit
        case "terminal", "execute_code", "process_manage", "close_terminal": return .run
        case "search_files", "session_search": return .search
        case "web_search", "web_extract", "x_search": return .web
        default: return tool.hasPrefix("browser_") ? .web : .other
        }
    }

    /// A short verb for one step in the expanded list.
    static func verb(for tool: String) -> String {
        switch category(of: tool) {
        case .read: return String(localized: "read")
        case .edit: return String(localized: "edit")
        case .run: return String(localized: "run")
        case .search: return String(localized: "search")
        case .web: return String(localized: "web")
        case .other: return tool.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func line(for steps: [ToolStep], agent: String) -> String {
        if steps.contains(where: { $0.state == .running }) {
            return String(localized: "\(agent) is working…")
        }
        var counts: [Category: Int] = [:]
        for step in steps { counts[category(of: step.name), default: 0] += 1 }
        let pieces = Category.allCases.compactMap { category -> String? in
            guard let count = counts[category] else { return nil }
            return phrase(category, count: count, mixed: counts.count > 1)
        }
        var line = "\(agent) \(joined(pieces))"
        let seconds = steps.compactMap(\.duration).reduce(0, +)
        if seconds >= 1 { line += " · " + duration(seconds) }
        let failed = steps.filter { $0.state == .failed }.count
        if failed > 0 { line += " · " + String(localized: "\(failed) failed") }
        return line
    }

    private static func phrase(_ category: Category, count: Int, mixed: Bool) -> String {
        switch category {
        case .read: return count == 1 ? "read 1 file" : "read \(count) files"
        case .edit: return count == 1 ? "edited 1 file" : "edited \(count) files"
        case .run: return count == 1 ? "ran 1 command" : "ran \(count) commands"
        case .search: return count == 1 ? "searched once" : "searched \(count) times"
        case .web: return "browsed the web"
        case .other:
            let noun = count == 1 ? "tool" : "tools"
            return mixed ? "used \(count) other \(noun)" : "used \(count) \(noun)"
        }
    }

    private static func joined(_ pieces: [String]) -> String {
        guard pieces.count > 1 else { return pieces.first ?? "" }
        return pieces.dropLast().joined(separator: ", ") + " and " + pieces[pieces.count - 1]
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
    }
}
