import Foundation

/// Voice replies: audio Hermes's `text_to_speech` tool made, and the text it was asked to say.
public enum SpokenAudio {
    static let toolName = "text_to_speech"

    /// Transcripts for the audio files a reply delivers, by path: what the `text_to_speech` calls
    /// in its turn said. Live, a call names its files. History keeps only the call's arguments,
    /// so there calls pair with the reply's audio in order, and only when the counts match: a
    /// transcript is never guessed.
    public static func transcripts(
        in items: [TranscriptItem], replyAt index: Int, audioPaths: [String]
    ) -> [String: String] {
        guard !audioPaths.isEmpty, items.indices.contains(index) else { return [:] }
        var calls: [ToolStep] = []
        turn: for item in items[..<index].reversed() {
            switch item.content {
            case .user: break turn
            case .activity(let steps):
                calls.insert(contentsOf: steps.filter { $0.name == toolName && $0.spokenText != nil }, at: 0)
            default: continue
            }
        }
        var transcripts: [String: String] = [:]
        var paths = audioPaths
        var unnamed: [ToolStep] = []
        for call in calls {
            let files = call.audioFiles ?? []
            if let path = files.first(where: paths.contains) {
                transcripts[path] = call.spokenText
                paths.removeAll(where: files.contains)
            } else {
                unnamed.append(call)
            }
        }
        if unnamed.count == paths.count {
            for (call, path) in zip(unnamed, paths) { transcripts[path] = call.spokenText }
        }
        return transcripts
    }

    /// A reply's text with its turn's speech files as `MEDIA:` lines, so they play.
    ///
    /// Hermes's messaging platforms attach a `text_to_speech` file to the reply themselves
    /// (`_collect_auto_append_media_tags` in `gateway/run.py`); the dashboard leaves it to the
    /// agent, which often writes the bare path ("Voice memo saved to: /…/tts_….mp3") instead.
    /// So a bare path with the tool's default file name becomes a `MEDIA:` line, and the last reply
    /// of a turn gets any file the turn's calls made that it doesn't name. History keeps only the
    /// calls' arguments, so there only the bare paths can be found.
    public static func delivered(_ text: String, in items: [TranscriptItem], replyAt index: Int) -> String {
        // Most replies name no speech file and end no turn that made one: they stay as they are.
        // The chat asks for every reply it shows on each update, so this skips reading each line.
        if !text.contains("tts_"), !isLastReplyOfTurn(items, index) || turnFiles(items, before: index).isEmpty {
            return text
        }
        var lines: [String] = []
        var named = Set<String>()
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            if inFence || trimmed.hasPrefix("MEDIA:") {
                if !inFence, trimmed.hasPrefix("MEDIA:") { named.insert(mediaPath(trimmed)) }
                lines.append(String(line))
                continue
            }
            let paths = speechPaths(in: line)
            guard !paths.isEmpty else {
                lines.append(String(line))
                continue
            }
            if let rest = withoutSpeechPaths(line, paths) { lines.append(rest) }
            for path in paths where !named.contains(path) {
                lines.append("MEDIA:\(path)")
                named.insert(path)
            }
        }
        if isLastReplyOfTurn(items, index) {
            for path in turnFiles(items, before: index) where !named.contains(path) {
                lines.append("MEDIA:\(path)")
                named.insert(path)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// `line` without the speech files it names; `nil` when nothing worth reading is left, such
    /// as "Voice memo saved to:", which only introduced the path that a player now stands for.
    static func withoutSpeechPaths(_ line: Substring, _ paths: [String]? = nil) -> String? {
        let paths = paths ?? speechPaths(in: line)
        guard !paths.isEmpty else { return String(line) }
        var rest = String(line)
        for path in paths {
            rest = rest.replacingOccurrences(of: "`\(path)`", with: "")
            rest = rest.replacingOccurrences(of: path, with: "")
        }
        while rest.contains("  ") { rest = rest.replacingOccurrences(of: "  ", with: " ") }
        rest = rest.trimmingCharacters(in: .whitespaces)
        let label = rest.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        let introducesThePath = rest.hasSuffix(":") && label.count <= 60
        return label.isEmpty || introducesThePath ? nil : rest
    }

    /// Absolute paths in `line` whose file name is the TTS tool's default.
    static func speechPaths(in line: Substring) -> [String] {
        line.split(whereSeparator: { $0.isWhitespace || "`\"'()<>[]".contains($0) }).compactMap { token in
            var path = String(token)
            while let last = path.last, ".,;:!?".contains(last) { path.removeLast() }
            guard path.hasPrefix("/") || path.hasPrefix("~/"), isSpeechFile(path) else { return nil }
            return path
        }
    }

    private static func mediaPath(_ line: String) -> String {
        line.dropFirst("MEDIA:".count).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "`\"'")))
    }

    private static func isLastReplyOfTurn(_ items: [TranscriptItem], _ index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        for item in items[(index + 1)...] {
            switch item.content {
            case .user: return true
            case .assistant: return false
            default: continue
            }
        }
        return true
    }

    /// The files the turn's `text_to_speech` calls made, in order.
    private static func turnFiles(_ items: [TranscriptItem], before index: Int) -> [String] {
        var files: [String] = []
        for item in items[..<index].reversed() {
            switch item.content {
            case .user: return files
            case .activity(let steps):
                files.insert(contentsOf: steps.filter { $0.name == toolName }.flatMap { $0.audioFiles ?? [] }, at: 0)
            default: continue
            }
        }
        return files
    }

    /// Whether `path` has the name Hermes's TTS tool gives the files it writes by default:
    /// `tts_<date>_<time>_<microseconds>.<ext>` (`_resolve_output_base` in `tools/tts_tool.py`).
    public static func isSpeechFile(_ path: String) -> Bool {
        (path as NSString).lastPathComponent.range(
            of: #"^tts_\d{8}_\d{6}(_\d+)?\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }
}

extension ToolStep {
    /// Reads a `text_to_speech` call's text and files from its `args` and `result`.
    mutating func readSpeech(args: JSONValue?, result: JSONValue? = nil) {
        guard name == SpokenAudio.toolName else { return }
        if let text = args?["text"]?.stringValue?.nonBlank { spokenText = text }
        if case .array(let paths) = result?["file_paths"] {
            audioFiles = paths.compactMap(\.stringValue)
        } else if let path = result?["file_path"]?.stringValue ?? args?["output_path"]?.stringValue {
            audioFiles = [path]
        }
    }
}
