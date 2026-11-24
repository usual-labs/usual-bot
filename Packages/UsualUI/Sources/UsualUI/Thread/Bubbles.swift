import HermesKit
import SwiftUI

/// Sizes to its content, up to `maximum`. `frame(maxWidth:)` would fill the width it's offered
/// instead, and a bubble's background would run past short text.
struct UpToWidth: Layout {
    var maximum = Theme.bubbleWidth

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(narrowed(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: narrowed(proposal))
    }

    private func narrowed(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? maximum, maximum), height: proposal.height)
    }
}

/// An agent's message: as wide as its text. Messages in a row share a corner where they meet.
struct AgentBubble<Content: View>: View {
    var joinsAbove = false
    var joinsBelow = false
    @ViewBuilder let content: Content
    @Zoomed private var maximum = Theme.bubbleWidth

    var body: some View {
        UpToWidth(maximum: maximum) {
            content
                .padding(.horizontal, Theme.bubblePadding)
                .padding(.vertical, 9)
                .background(
                    Theme.bubble,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: joinsAbove ? 6 : 18, bottomLeadingRadius: joinsBelow ? 6 : 18,
                        bottomTrailingRadius: 18, topTrailingRadius: 18))
        }
        .padding(.trailing, Theme.agentSideRoom)
    }
}

extension View {
    /// A card in a conversation: on the agent's side, as wide as a message can be. The system's
    /// fill for large areas holding other controls, so it sits on the pane in both appearances
    /// and its buttons keep their own look; no shadow, as it doesn't float.
    func cardSurface() -> some View {
        padding(16)
            // Leading, or a card with short lines floats towards its middle.
            .zoomedFrame(maxWidth: Theme.bubbleWidth, alignment: .leading)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.trailing, Theme.agentSideRoom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }

    /// A card's button: the system's bordered one, prominent for what the card expects you to
    /// choose. Large on the Mac, where regular is a toolbar's size; on iPhone, large only when
    /// stacked full width (`fill`), as an action sheet's are.
    @ViewBuilder func cardButton(prominent: Bool = false, fill: Bool = false) -> some View {
        let sized = controlSize(cardButtonSize(fill: fill))
        if prominent {
            sized.buttonStyle(.inkProminent)
        } else {
            sized.buttonStyle(.clickable(.bordered))
        }
    }

    /// A faint fill under the pointer, on the Mac.
    func hoverHighlight(in shape: some Shape) -> some View {
        modifier(HoverHighlight(shape: shape))
    }
}

private func cardButtonSize(fill: Bool) -> ControlSize {
    #if os(iOS)
        fill ? .large : .regular
    #else
        .large
    #endif
}

private struct HoverHighlight<Highlight: Shape>: ViewModifier {
    let shape: Highlight
    @State private var isHovering = false
    /// A window behind others still tracks the pointer passing over it.
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .background(isHovering && appearsActive ? Theme.selection.opacity(0.5) : .clear, in: shape)
            .animation(.easeOut(duration: 0.1), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension AnyTransition {
    /// Your message rising out of the message box.
    static var rise: AnyTransition {
        asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12))
                .combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)),
            removal: .identity)
    }

    /// A reply or card settling in under the last message.
    static var settle: AnyTransition {
        asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity)
    }
}

/// What the agent is doing, under the last message: its avatar at work, and the words shimmering.
struct WorkingRow: View {
    /// The words, and what VoiceOver reads when that differs: it leaves Hermes's faces out.
    struct Words: Equatable {
        let text: String
        var spoken: String?
    }

    let words: Words
    @Environment(\.chatContact) private var contact

    init(text: String) { words = Words(text: text) }
    init(_ words: Words) { self.words = words }

    var body: some View {
        HStack(spacing: 8) {
            if let contact {
                AgentAvatar(contact: contact.with(activity: .working), size: 24)
            }
            ShimmerText(text: words.text)
                .accessibilityLabel(words.spoken ?? words.text)
        }
        .padding(.leading, 8)
        .zoomedFrame(minHeight: 28)
    }

    /// Shown while a reply is written out of sight, with streaming turned off in Settings.
    nonisolated static var writing: String { String(localized: "Writing…") }

    nonisolated static func text(for state: ThreadState) -> String { words(for: state).text }

    /// What the turn is doing, for a chat that shows no reply being written: a wait or the
    /// agent's reasoning first, then the kind of tool running, then the face and verb Hermes
    /// picked for this model call.
    nonisolated static func words(for state: ThreadState) -> Words {
        if !state.draft.isEmpty { return Words(text: writing) }
        if let said = state.live.status ?? state.live.thought { return Words(text: said) }
        if case .activity(let steps) = state.items.last?.content,
            let step = steps.last(where: { $0.state == .running })
        {
            return Words(text: String(localized: "\(ActivitySummary.doing(step.name))…"))
        }
        if let mood = state.live.mood {
            let verb = String(localized: "\(mood.verb)…")
            return Words(text: [mood.face, verb].compactMap(\.self).joined(separator: " "), spoken: verb)
        }
        return Words(text: String(localized: "Thinking…"))
    }
}

/// Grey words with a lighter band passing over them. Reduce Motion leaves them plain.
struct ShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            // The band starts and ends off the text, so the words rest between passes.
            let band = Self.band(at: context.date.timeIntervalSinceReferenceDate)
            Text(text)
                .scaledFont(size: 13)
                .lineLimit(1, accessibility: 3)
                .foregroundStyle(reduceMotion ? AnyShapeStyle(Theme.secondaryInk) : AnyShapeStyle(Self.fill(at: band)))
        }
    }

    /// Where the lighter band is, from -0.4 to 1.4, `time` seconds in.
    static func band(at time: TimeInterval) -> Double {
        time.truncatingRemainder(dividingBy: period) / period * 1.8 - 0.4
    }

    static func fill(at band: Double) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Theme.secondaryInk, location: band - 0.2),
                .init(color: Theme.ink, location: band),
                .init(color: Theme.secondaryInk, location: band + 0.2),
            ], startPoint: .leading, endPoint: .trailing)
    }
}
