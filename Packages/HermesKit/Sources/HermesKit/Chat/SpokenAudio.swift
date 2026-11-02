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
