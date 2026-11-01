#if DEBUG
    import Foundation
    import Synchronization
    import os

    /// Debug builds only. Launched with `USUALBOT_RECORD_FRAMES=1`, the app appends every socket frame
    /// to `<temporary directory>/usualbot-frames.jsonl`, one `{"dir":"in"|"out","frame":…}` per line,
    /// so real gateway traffic can be turned into test fixtures. Frames hold your conversations:
    /// anonymise them before committing anything. Answers to masked prompts and vault secrets are
    /// blanked (`redacted`), and replies to `sensitive` calls aren't recorded (`JSONRPCChannel`).
    enum FrameRecorder {
        static let fileURL: URL? = {
            guard ProcessInfo.processInfo.environment["USUALBOT_RECORD_FRAMES"] == "1" else { return nil }
            let url = FileManager.default.temporaryDirectory.appending(path: "usualbot-frames.jsonl")
            Logger(subsystem: "UsualBot", category: "gateway")
                .info("Recording socket frames to \(url.path, privacy: .public)")
            return url
        }()

        private static let lock = Mutex(())
        /// Calls whose params hold secrets, and which params.
        private static let secretParams = ["vault.add": ["secret"], "vault.unlock": ["password"]]
        /// Tests: sees every line as it would be written.
        static let observer = Mutex<(@Sendable (String) -> Void)?>(nil)

        static func record(_ direction: String, _ text: String) {
            let observing = observer.withLock { $0 != nil }
            guard fileURL != nil || observing else { return }
            let frame = (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .string(text)
            let entry: JSONValue = ["dir": .string(direction), "frame": direction == "out" ? redacted(frame) : frame]
            guard var line = try? JSONEncoder().encode(entry) else { return }
            observer.withLock { $0?(String(decoding: line, as: UTF8.self)) }
            guard let fileURL else { return }
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

        /// An outgoing frame without what you typed: the `value` of any answer to a server request
        /// (master passwords, codes, logins, sudo passwords, secrets) and the secret params of calls.
        static func redacted(_ frame: JSONValue) -> JSONValue {
            guard case .object(var fields) = frame else { return frame }
            if case .object(var result)? = fields["result"], result["value"] != nil {
                result["value"] = ""
                fields["result"] = .object(result)
            }
            if let keys = frame["method"]?.stringValue.flatMap({ secretParams[$0] }),
                case .object(var params)? = fields["params"]
            {
                for key in keys where params[key] != nil { params[key] = "" }
                fields["params"] = .object(params)
            }
            return .object(fields)
        }
    }
#endif
