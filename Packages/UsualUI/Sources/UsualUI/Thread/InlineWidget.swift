import HermesKit
import SwiftUI

extension EnvironmentValues {
    /// Whether widgets run here; where they don't (the ⌥Space panel), they show as a card.
    @Entry var runsWidgets = true
}

/// A `::preview{file="…"}` page in a reply, running live in the message as in Hermes's desktop
/// app. It sizes itself to the page: the height follows it, within `WidgetPage`'s limits, and the
/// width is the page's first measured width.
struct InlineWidget: View {
    let directive: WidgetDirective
    /// The reply is still being written, so the page may be too.
    var isBeingWritten = false

    @Environment(\.media) private var store
    @Environment(\.mediaProfile) private var profile
    @Environment(\.runsWidgets) private var runs
    @Environment(\.messageTextSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    @State private var phase = Phase.loading
    /// On screen now, and whether its page is running: it stops a while after it scrolls away.
    @State private var isVisible = false
    @State private var isRunning = false
    /// The page's own height, before clamping, and its width once measured.
    @State private var pageHeight: CGFloat?
    @State private var pageWidth: CGFloat?
    /// How wide the frame came out, which a page wider than it scrolls across.
    @State private var frameWidth: CGFloat?

    enum Phase: Equatable {
        case loading
        case loaded(String)
        case failed(String)
    }

    /// How long a page keeps running off screen, so scrolling past and back keeps its state.
    private static let offscreenGrace = Duration.seconds(20)

    private var name: String { (directive.file as NSString).lastPathComponent }

    var body: some View {
        Group {
            if !runs {
                WidgetCard(
                    name: name, detail: String(localized: "Open the chat in Usual Bot to use this widget."))
            } else if case .failed(let reason) = phase {
                WidgetCard(name: name, detail: String(localized: "Couldn't show this widget. \(reason)"))
            } else {
                frame
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Widget \(name)"))
        .task(id: LoadKey(file: directive.file, profile: profile, isBeingWritten: isBeingWritten)) {
            guard runs, !isBeingWritten else { return }
            await load()
        }
    }

    private var height: CGFloat {
        pageHeight.map(WidgetPage.clamped) ?? WidgetPage.startHeight(directive.height)
    }

    @ViewBuilder private var frame: some View {
        Group {
            if case .loaded(let html) = phase, isRunning {
                WidgetFrame(html: html, theme: theme, scrolls: scrolls, onMessage: receive)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.ink.opacity(0.04))
                    .overlay {
                        if phase == .loading { ProgressView().controlSize(.small) }
                    }
            }
        }
        .frame(height: height)
        .frame(maxWidth: pageWidth ?? .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { frameWidth = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        .task(id: isVisible) {
            if isVisible {
                isRunning = true
            } else if isRunning {
                // sleep-ok: a page scrolled away keeps running a little, in case you come back.
                try? await Task.sleep(for: Self.offscreenGrace)
                if !Task.isCancelled { isRunning = false }
            }
        }
    }

    /// Taller than the frame can grow, or wider than the message: it scrolls inside, as a page in
    /// Hermes's frame does. Otherwise a swipe over it scrolls the chat.
    private var scrolls: Bool {
        (pageHeight ?? 0) > WidgetPage.maxHeight || (pageWidth ?? 0) > (frameWidth ?? .infinity) + 1
    }

    private func receive(_ message: WidgetMessage) {
        switch message {
        case .size(let height, let width):
            if abs(height - (pageHeight ?? WidgetPage.startHeight(directive.height))) > WidgetPage.tolerance {
                pageHeight = height
            }
            // Taken once: following it would shrink a page whose parts are a share of its width,
            // a little more each time.
            if pageWidth == nil, width > 0 { pageWidth = width }
        }
    }

    private var theme: WidgetPage.Theme {
        func css(_ color: Color) -> String {
            let resolved = color.resolve(in: environment)
            return WidgetPage.css(
                red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue),
                opacity: Double(resolved.opacity))
        }
        return WidgetPage.Theme(
            dark: colorScheme == .dark, foreground: css(Theme.ink), mutedForeground: css(Theme.secondaryInk),
            accent: css(Theme.link), border: css(Theme.border), card: css(Theme.codeFill),
            fontSize: Double(textSize))
    }

    private func load() async {
        do {
            guard let store, let profile else { throw GatewayError.disconnected }
            // Read again each time: the agent updates a widget by rewriting its page.
            let data = try await store.file(at: directive.file, profile: profile, fresh: true)
            guard let html = String(data: data, encoding: .utf8) else {
                phase = .failed(String(localized: "\(name) isn't a web page."))
                return
            }
            phase = .loaded(html)
        } catch {
            phase = .failed(AppModel.describe(error))
        }
    }

    private struct LoadKey: Equatable {
        let file: String
        let profile: String?
        let isBeingWritten: Bool
    }
}

/// A widget shown as what it is instead of running: its name, and why.
struct WidgetCard: View {
    let name: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .foregroundStyle(Theme.secondaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).scaledFont(size: 13, weight: .semibold).foregroundStyle(Theme.ink)
                Text(detail).scaledFont(size: 12.5).foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }
}
