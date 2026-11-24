import HermesKit
import SwiftUI

/// The share extension's whole screen, which is mostly a moment: it saves what you shared in the
/// folder the app shares (`ShareContainer`) and opens Usual Bot, where you choose a chat for it
/// (`SharedItemSheet`). It says more only when there's nothing to save or the app didn't open.
public struct ShareView: View {
    let providers: [NSItemProvider]
    let container: ShareContainer?
    /// Opens the app at its `share` link; whether it did.
    let openApp: () async -> Bool
    /// Closes the extension: the item is saved, or there was nothing to do.
    let done: () -> Void
    let cancel: () -> Void

    public init(
        providers: [NSItemProvider], container: ShareContainer?, openApp: @escaping () async -> Bool,
        done: @escaping () -> Void, cancel: @escaping () -> Void
    ) {
        self.providers = providers
        self.container = container
        self.openApp = openApp
        self.done = done
        self.cancel = cancel
    }

    private enum Phase: Equatable {
        case loading
        case nothing([String])
        case failed(String)
        /// Saved, but the app didn't open.
        case saved
    }

    @State private var phase = Phase.loading
    @State private var incoming = FileManager.default.temporaryDirectory.appending(
        path: "Shared-\(UUID().uuidString)", directoryHint: .isDirectory)

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                if phase == .loading {
                    Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                }
                Spacer()
                if phase != .loading {
                    Button("Done", action: done)
                        .fontWeight(.semibold)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .buttonStyle(.clickable)
            .overlay { Text("Usual Bot").font(.headline).accessibilityAddTraits(.isHeader) }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Divider().overlay(Theme.border)
            content
        }
        .background(Theme.window)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .task { await share() }
        .onDisappear { try? FileManager.default.removeItem(at: incoming) }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 14) {
                ProgressView()
                Text("Opening Usual Bot…").font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .nothing(let problems):
            notice(
                "square.and.arrow.up.trianglebadge.exclamationmark", String(localized: "Nothing to share"),
                problems.isEmpty
                    ? String(localized: "Usual Bot takes text, web links, images and files.")
                    : problems.joined(separator: " "))
        case .failed(let reason):
            notice("exclamationmark.triangle", String(localized: "Couldn't share it"), reason)
        case .saved:
            notice(
                "tray.and.arrow.down", String(localized: "Open Usual Bot to send it"),
                String(localized: "It's saved on this device. Usual Bot asks which chat it goes to when you open it."))
        }
    }

    private func notice(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityHidden(true)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func share() async {
        guard phase == .loading else { return }
        guard let container else {
            return show(
                .failed(String(localized: "This build of Usual Bot was made without the App Group that sharing needs."))
            )
        }
        let content = await ShareLoader.load(providers, into: incoming)
        guard !content.isEmpty else { return show(.nothing(content.problems)) }
        do {
            try container.add(content)
        } catch {
            return show(.failed(String(localized: "Couldn't save it: \(error.localizedDescription)")))
        }
        if await openApp() { done() } else { show(.saved) }
    }

    private func show(_ phase: Phase) {
        self.phase = phase
        let words: String? =
            switch phase {
            case .loading: nil
            case .nothing: String(localized: "Nothing to share")
            case .failed: String(localized: "Couldn't share it")
            case .saved: String(localized: "Open Usual Bot to send it")
            }
        if let words { AccessibilityNotification.Announcement(words).post() }
    }
}
