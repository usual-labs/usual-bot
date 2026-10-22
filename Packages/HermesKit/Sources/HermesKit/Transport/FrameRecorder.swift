#if DEBUG
    import Foundation
    import Synchronization
    import os

    /// Debug builds only. Launched with `USUALBOT_RECORD_FRAMES=1`, the app appends every socket frame
    /// to `<temporary directory>/usualbot-frames.jsonl`, one `{"dir":"in"|"out","frame":…}` per line,
    /// so real gateway traffic can be turned into test fixtures. Frames hold your conversations:
    /// anonymise them before committing anything.
    enum FrameRecorder {
        static let fileURL: URL? = {
            guard ProcessInfo.processInfo.environment["USUALBOT_RECORD_FRAMES"] == "1" else { return nil }
            let url = FileManager.default.temporaryDirectory.appending(path: "usualbot-frames.jsonl")
            Logger(subsystem: "UsualBot", category: "gateway")
                .info("Recording socket frames to \(url.path, privacy: .public)")
            return url
        }()

        private static let lock = Mutex(())

        static func record(_ direction: String, _ text: String) {
            guard let fileURL else { return }
            let frame = (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .string(text)
            let entry: JSONValue = ["dir": .string(direction), "frame": frame]
            guard var line = try? JSONEncoder().encode(entry) else { return }
            line.append(0x0A)
            lock.withLock { _ in
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: line)
                } else {
                    try? line.write(to: fileURL)
                }
            }
        }
    }
#endif
