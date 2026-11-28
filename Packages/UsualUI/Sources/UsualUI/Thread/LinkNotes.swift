import HermesKit
import SwiftUI

/// What a bad network looks like: the chat stays readable, and the link's state is said in small
/// places. Under a chat's name (`NamePill`), in a strip above the message box once the link has
/// been down a while (`ConnectionNotice`), under the spinner of a chat slow to load
/// (`SlowLoadingNote`), and on iPhone between the chat list's two buttons (`LinkPill`).
extension EnvironmentValues {
    @Entry var linkStatus: LinkStatus = .quiet
    @Entry var linkRetry: LinkRetry?
}

/// Tries the gateway again now, rather than at the next backoff.
struct LinkRetry {
    let retry: () -> Void
}

/// How long the link has to be down before anything says so, so a quick reconnect doesn't flicker.
let linkNoteDelay: Duration = .milliseconds(1500)

extension View {
    /// Keeps `note` in `shown` once it has held for `linkNoteDelay`; clears it at once.
    func delayedLinkNote(_ note: LinkNote?, into shown: Binding<LinkNote?>) -> some View {
        task(id: note) {
            guard let note else {
                shown.wrappedValue = nil
                return
            }
            if shown.wrappedValue == nil {
                try? await Task.sleep(for: linkNoteDelay)
                guard !Task.isCancelled else { return }
            }
            shown.wrappedValue = note
        }
    }
}

/// Stands in while a note is hidden: a `task` on an empty `Group` never runs, so the wait that
/// shows the note needs a view that's always there. Takes no room in a stack with no spacing.
struct LinkNoteAnchor: View {
    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

/// The line under a chat's name: a spinner while the link is coming back, then what's happening.
struct LinkNoteLine: View {
    let note: LinkNote
    let size: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            if note != .noNetwork {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .zoomedFrame(width: 10, height: 10)
            }
            Text(note.text)
                .scaledFont(size: size)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1)
        }
    }
}

/// Above the message box once the link has been down for `delay`: the chat on screen is the copy
/// from before, as of when it was last attached, and Retry tries again now. In the plan-limit
/// warning's glass and type.
struct ConnectionNotice: View {
    /// "Forge's chat", "Launch crew".
    let subject: String
    let asOf: Date?
    var delay: Duration = .seconds(10)
    @Environment(\.linkStatus) private var status
    @Environment(\.linkRetry) private var retry
    @State private var isShown = false

    var body: some View {
        Group {
            if isShown, status.applies, !status.isOnline {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: status.hasNetwork ? "wifi.exclamationmark" : "wifi.slash")
                        .zoomedFont(size: 12)
                        .foregroundStyle(Theme.needsYouInk)
                        .accessibilityHidden(true)
                    Text(text)
                        .scaledFont(size: 12.5)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if status.hasNetwork, let retry {
                        Button("Retry", action: retry.retry)
                            .buttonStyle(.clickable(.borderless))
                            .scaledFont(size: 12.5, weight: .semibold)
                            .foregroundStyle(Theme.ink)
                            .accessibilityHint(Text("Tries your gateway again now"))
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .combine)
                .padding(.bottom, 6)
                .transition(.opacity)
            } else {
                LinkNoteAnchor()
            }
        }
        .animation(.smooth(duration: 0.2), value: isShown && !status.isOnline)
        .task(id: status.offlineSince) {
            guard let since = status.offlineSince else {
                isShown = false
                return
            }
            let waited = Duration.seconds(Date.now.timeIntervalSince(since))
            if waited < delay { try? await Task.sleep(for: delay - waited) }
            guard !Task.isCancelled else { return }
            isShown = true
        }
    }

    private var text: String {
        let problem =
            status.hasNetwork
            ? String(localized: "Can't reach your gateway.") : String(localized: "No network.")
        guard let asOf else { return problem + " " + String(localized: "This is \(subject) as last loaded.") }
        let time =
            Calendar.current.isDateInToday(asOf)
            ? asOf.formatted(date: .omitted, time: .shortened) : asOf.formatted(date: .abbreviated, time: .shortened)
        return problem + " " + String(localized: "This is \(subject) as of \(time).")
    }
}

/// Under the spinner of a chat with nothing saved to show, once it has loaded for `delay`: it
/// keeps trying by itself, so there's nothing to press.
struct SlowLoadingNote: View {
    let name: String
    let since: Date?
    var delay: Duration = .seconds(10)
    @State private var isShown = false

    var body: some View {
        Group {
            if isShown {
                Text("\(name)'s chat is still loading. The network is slow, so this can take a minute.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .transition(.opacity)
            } else {
                LinkNoteAnchor()
            }
        }
        .animation(.smooth(duration: 0.2), value: isShown)
        .task(id: since) {
            guard let since else {
                isShown = false
                return
            }
            let waited = Duration.seconds(Date.now.timeIntervalSince(since))
            if waited < delay { try? await Task.sleep(for: delay - waited) }
            guard !Task.isCancelled else { return }
            isShown = true
        }
    }
}

#if os(iOS)
    /// Between the chat list's Settings and New Bot buttons while the link is down: what's
    /// happening, in the same glass. Opens Settings, where the gateway's state and Try Again are.
    struct LinkPill: View {
        let note: LinkNote
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 7) {
                    if note == .noNetwork {
                        Image(systemName: "wifi.slash")
                            .zoomedFont(size: 14)
                            .foregroundStyle(Theme.needsYouInk)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(note.text)
                        .scaledFont(size: 15, weight: .medium)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .zoomedFrame(height: 36)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .accessibilityHint(Text("Shows your gateway's connection in Settings"))
        }
    }
#endif
