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

    var body: some View {
        UpToWidth {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Theme.bubble,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: joinsAbove ? 6 : 18, bottomLeadingRadius: joinsBelow ? 6 : 18,
                        bottomTrailingRadius: 18, topTrailingRadius: 18))
        }
    }
}

extension View {
    /// A card in a conversation: on the agent's side, as wide as a message can be.
    func cardSurface() -> some View {
        padding(16)
            .frame(maxWidth: Theme.bubbleWidth)
            .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }

    /// A faint fill under the pointer, on the Mac.
    func hoverHighlight(in shape: some Shape) -> some View {
        modifier(HoverHighlight(shape: shape))
    }
}

private struct HoverHighlight<Highlight: Shape>: ViewModifier {
    let shape: Highlight
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(isHovering ? Theme.selection.opacity(0.5) : .clear, in: shape)
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
    let text: String
    @Environment(\.chatContact) private var contact

    var body: some View {
        HStack(spacing: 8) {
            if let contact {
                AgentAvatar(contact: contact.with(activity: .working), size: 24)
            }
            ShimmerText(text: text)
        }
        .padding(.leading, 8)
        .frame(minHeight: 28)
    }
}

/// Grey words with a lighter band passing over them. Reduce Motion leaves them plain.
struct ShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            // The band starts and ends off the text, so the words rest between passes.
            let band = time.truncatingRemainder(dividingBy: Self.period) / Self.period * 1.8 - 0.4
            Text(text)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(reduceMotion ? AnyShapeStyle(Theme.secondaryInk) : AnyShapeStyle(fill(at: band)))
        }
    }

    private func fill(at band: Double) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Theme.secondaryInk, location: band - 0.2),
                .init(color: Theme.ink, location: band),
                .init(color: Theme.secondaryInk, location: band + 0.2),
            ], startPoint: .leading, endPoint: .trailing)
    }
}
