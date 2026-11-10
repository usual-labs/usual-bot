import Foundation
import Observation
import os

/// What you've typed and not sent, for each chat and room. It never goes to the gateway, so your
/// other devices don't have it. On disk it lives in Application Support, because the system may
/// empty Caches; it's left out of backups, and deleted on sign-out.
@MainActor
@Observable
public final class Drafts {
    private var texts: [Contact.ID: String] = [:]
    /// `nil` keeps drafts only while the app runs, as the demo does.
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private var gateway: GatewayAddress?
    /// A change waiting to be written.
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    private static let log = Logger(subsystem: "UsualBot", category: "drafts")

    static var deviceDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "UsualBot/Drafts", directoryHint: .isDirectory)
    }

    init(directory: URL? = nil) {
        self.directory = directory
    }

    /// The text in `id`'s message box; empty when there is none.
    public subscript(id: Contact.ID) -> String {
        get { texts[id] ?? "" }
        set {
            guard newValue != self[id] else { return }
            texts[id] = newValue.isEmpty ? nil : newValue
            saveSoon()
        }
    }

    /// Writes a change that's still waiting, before the app goes away.
    public func save() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        guard let url = fileURL, var directory else { return }
        // Spaces and line breaks alone aren't a draft worth keeping.
        let kept = texts.filter { $0.value.nonBlank != nil }
        do {
            guard !kept.isEmpty else {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                return
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // On the folder: an atomic write replaces the file, and with it anything set on the file.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            try JSONEncoder().encode(kept).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            Self.log.error("Couldn't save drafts: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads what this device keeps for `gateway`.
    func load(for gateway: GatewayAddress) {
        self.gateway = gateway
        guard let url = fileURL else { return }
        let stored = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode([Contact.ID: String].self, from: $0)
        }
        texts = stored ?? [:]
    }

    /// Forgets everything on signing out.
    func clear() {
        pendingSave?.cancel()
        pendingSave = nil
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        texts = [:]
        gateway = nil
    }

    /// A Bot renamed on the gateway keeps its draft.
    func move(from old: Contact.ID, to new: Contact.ID) {
        guard let text = texts.removeValue(forKey: old) else { return }
        if texts[new] == nil { texts[new] = text }
        saveSoon()
    }

    /// Drops the draft of a Bot or room that's gone.
    func forget(_ id: Contact.ID) {
        if texts.removeValue(forKey: id) != nil { saveSoon() }
    }

    /// Typing writes at most twice a second, so a quit that isn't a clean one loses half a
    /// second at most.
    private func saveSoon() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private var fileURL: URL? {
        guard let directory, let gateway else { return nil }
        return directory.appending(path: gateway.fileName)
    }
}
