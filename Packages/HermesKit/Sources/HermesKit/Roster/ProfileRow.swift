import Foundation

/// One row of `profiles.list`: a Hermes profile plus its "Bot Chat" summary.
/// Decoding is lenient field by field, so one odd value never empties the whole roster.
struct ProfileRow: Decodable, Sendable {
    let name: String
    let displayName: String?
    let description: String?
    let model: String?
    let provider: String?
    let skillCount: Int?
    let bot: BotMeta?
    let canonicalSession: SessionSummary?

    /// The desktop's per-bot presentation settings, stored in `profile.yaml` under
    /// `ui_meta['hermes-bots']`.
    struct BotMeta: Decodable, Sendable {
        let title: String?
        let color: String?
        let hidden: Bool?
        let pinned: Bool?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try? container.decodeIfPresent(String.self, forKey: .title)
            color = try? container.decodeIfPresent(String.self, forKey: .color)
            hidden = try? container.decodeIfPresent(Bool.self, forKey: .hidden)
            pinned = try? container.decodeIfPresent(Bool.self, forKey: .pinned)
        }

        private enum CodingKeys: String, CodingKey { case title, color, hidden, pinned }
    }

    /// The profile's one long-lived conversation, titled exactly "Bot Chat".
    struct SessionSummary: Decodable, Sendable {
        let id: String
        let resolvedId: String?
        let preview: String?
        /// Unix seconds.
        let lastActive: Double?
        let messageCount: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            resolvedId = try? container.decodeIfPresent(String.self, forKey: .resolvedId)
            preview = try? container.decodeIfPresent(String.self, forKey: .preview)
            lastActive = try? container.decodeIfPresent(Double.self, forKey: .lastActive)
            messageCount = try? container.decodeIfPresent(Int.self, forKey: .messageCount)
        }

        private enum CodingKeys: String, CodingKey { case id, resolvedId, preview, lastActive, messageCount }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        provider = try? container.decodeIfPresent(String.self, forKey: .provider)
        skillCount = try? container.decodeIfPresent(Int.self, forKey: .skillCount)
        bot = (try? container.decodeIfPresent(UIMeta.self, forKey: .uiMeta))?.bot
        canonicalSession = try? container.decodeIfPresent(SessionSummary.self, forKey: .canonicalSession)
    }

    private struct UIMeta: Decodable {
        let bot: BotMeta?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bot = try? container.decodeIfPresent(BotMeta.self, forKey: .bot)
        }

        private enum CodingKeys: String, CodingKey { case bot = "hermes-bots" }
    }

    private enum CodingKeys: String, CodingKey {
        case name, displayName, description, model, provider, skillCount, uiMeta, canonicalSession
    }
}

struct ProfileList: Decodable, Sendable {
    let profiles: [ProfileRow]
}

extension Contact {
    /// A sidebar contact for a profile, or `nil` when the user hid that bot.
    init?(profile: ProfileRow) {
        guard profile.bot?.hidden != true else { return nil }
        let name = [profile.bot?.title, profile.displayName].lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let chat = profile.canonicalSession
        let preview = [chat?.preview.map(Self.plainPreview), profile.description].lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        self.init(
            id: profile.name,
            name: name ?? Self.friendlyName(forProfile: profile.name),
            tint: profile.bot?.color,
            preview: preview,
            lastActive: chat?.lastActive.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
            isPinned: profile.bot?.pinned ?? false,
            chatID: chat.map { $0.resolvedId ?? $0.id },
            details: AgentDetails(
                profile: profile.name, description: profile.description?.nonBlank, model: profile.model?.nonBlank,
                provider: profile.provider?.nonBlank, skillCount: profile.skillCount))
    }

    /// Previews are the start of the last message, usually Markdown, cut at 80 characters by the
    /// gateway (so bold or code can be left unclosed). The list shows them as plain text.
    static func plainPreview(_ text: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var plain = (try? AttributedString(markdown: text, options: options)).map { String($0.characters) } ?? text
        for marker in ["**", "__", "~~", "`"] {
            plain = plain.replacingOccurrences(of: marker, with: "")
        }
        let trimmed = plain.trimmingCharacters(in: .whitespaces).drop { "#>".contains($0) }
        return trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The name an untitled profile shows, matching the official app: the primary profile, literally
    /// called `default`, is "Hermes"; others read as words, so `job-scout` becomes "Job Scout".
    static func friendlyName(forProfile name: String) -> String {
        if name.lowercased() == "default" { return "Hermes" }
        let words = name.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard !words.isEmpty else { return name }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
