import AppKit
import Carbon.HIToolbox

/// Uses a second process because Carbon always rejects duplicates within the same process,
/// but accepts other apps' registrations unless exclusivity is requested.
@main
struct HotKeyCheck {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor static func main() {
        do {
            try check()
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor private static func check() throws {
        _ = NSApplication.shared
        let occupied = HotKey.Combo(
            keyCode: UInt32(kVK_F19), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey), label: "F19")
        let alternate = HotKey.Combo(
            keyCode: UInt32(kVK_F20), modifiers: occupied.modifiers, label: "F20")

        if CommandLine.arguments.contains("--hold") {
            let key = HotKey([occupied]) {}
            guard key.combo != nil else { throw Failure(description: "Could not reserve the test shortcut.") }
            FileHandle.standardOutput.write(Data("ready\n".utf8))
            withExtendedLifetime(key) { RunLoop.main.run() }
            return
        }

        let holder = Process()
        let output = Pipe()
        holder.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        holder.arguments = ["--hold"]
        holder.standardOutput = output
        try holder.run()
        output.fileHandleForWriting.closeFile()
        defer {
            if holder.isRunning { holder.terminate() }
            holder.waitUntilExit()
        }
        var ready = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
            ready.append(byte)
            if byte == Data([10]) { break }
        }
        guard String(data: ready, encoding: .utf8) == "ready\n" else {
            throw Failure(description: "The shortcut holder did not become ready.")
        }

        let blocked = HotKey([occupied]) {}
        defer { blocked.unregister() }
        guard blocked.combo == nil else {
            throw Failure(description: "An occupied shortcut must be refused instead of shared with another app.")
        }
        let fallback = HotKey([occupied, alternate]) {}
        guard fallback.combo == alternate else { throw Failure(description: "Did not choose the available fallback.") }
        fallback.unregister()

        let replacement = HotKey([alternate]) {}
        guard replacement.combo == alternate else {
            throw Failure(description: "Unregister did not release the shortcut.")
        }
        replacement.unregister()

        let suite = "UsualBotShortcutCheck-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(description: "No test preferences.") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = QuickMessageShortcut(defaults: defaults, defaultCombos: [occupied, alternate])
        guard setup.label == alternate.label else { throw Failure(description: "Setup did not choose the fallback.") }
        setup.beginRecording()
        setup.disable()
        guard !setup.isRecording else { throw Failure(description: "Disable left the recorder listening for keys.") }
        setup.endRecording()
        guard !setup.isRecording, !setup.isEnabled, setup.label == nil else {
            throw Failure(description: "Disable must end recording without restoring the shortcut.")
        }
        setup.beginRecording()
        setup.restoreDefault()
        guard !setup.isRecording else {
            throw Failure(description: "Restore Default left the recorder listening for keys.")
        }
        setup.endRecording()
        guard !setup.isRecording, setup.isEnabled, setup.label == alternate.label else {
            throw Failure(description: "Restore Default must end recording and keep the accepted shortcut.")
        }
        setup.set(occupied)
        guard setup.label == alternate.label, setup.problem != nil else {
            throw Failure(description: "A refused change must keep the previous shortcut and explain why.")
        }
        setup.disable()
        let restored = QuickMessageShortcut(defaults: defaults, defaultCombos: [alternate])
        guard !restored.isEnabled, restored.label == nil else {
            throw Failure(description: "A disabled shortcut must stay disabled after relaunch.")
        }

        holder.terminate()
        holder.waitUntilExit()
        let released = HotKey([occupied]) {}
        defer { released.unregister() }
        guard released.combo == occupied else {
            throw Failure(description: "The other process did not release its shortcut.")
        }
        print("Global shortcut conflicts, fallback, release, recording and persistence passed.")
    }
}
