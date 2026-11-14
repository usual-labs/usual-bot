import HermesKit
import SwiftUI

extension EnvironmentValues {
    /// Opens the Bot's page or the room's details: an iPhone conversation flicked left does.
    @Entry var showConversationDetails: (() -> Void)?
}

#if os(iOS)
    import UIKit

    // iPhone's sideways swipes in a conversation, as in Grok's app: a message pulled right is
    // replied to; the conversation pulled left shows when each message was sent, and flicked left
    // opens the Bot's page or the room's details.

    /// How far the conversation is pulled left to show the times.
    @MainActor @Observable
    final class TimeReveal {
        var offset: CGFloat = 0
        /// How far the pull goes before it resists: room for a time, past the margin.
        var width: CGFloat = 64
    }

    /// Moves the conversation with the pull. Its own view, so only it and the times follow each
    /// step of the swipe, not every message.
    struct RevealShift: ViewModifier {
        let reveal: TimeReveal

        func body(content: Content) -> some View {
            content.offset(x: -reveal.offset)
        }
    }

    /// A message's time, just past the conversation's right edge, which the pull brings into view.
    struct RevealedTime: View {
        let date: Date
        @Environment(TimeReveal.self) private var reveal: TimeReveal?

        var body: some View {
            if let reveal {
                Text(DateLabels.time(of: date))
                    .scaledFont(size: 11.5)
                    .foregroundStyle(Theme.secondaryInk)
                    .monospacedDigit()
                    .fixedSize()
                    // On a wide iPad the margin is on screen, so the time fades in rather than
                    // waiting there.
                    .opacity(min(1, reveal.offset / max(reveal.width, 1)))
                    // A box with no width at the row's edge, which the time runs out of to the
                    // right: past the margin, off screen until the pull.
                    .frame(width: 0, alignment: .leading)
                    .offset(x: ThreadPane.contentMargin)
                    // The menu says when a message was sent; VoiceOver can't pull.
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }

    /// A pull past `limit` goes on at a quarter of the finger's pace.
    func resisted(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        guard distance > limit else { return max(0, distance) }
        return limit + (distance - limit) / 4
    }

    /// A pan that starts only sideways, in one direction. A UIKit recognizer, because a SwiftUI
    /// drag inside a scroll view either stops it scrolling or runs alongside it; this one makes the
    /// scrolling wait only until it's clear the finger is going sideways.
    struct SidewaysPan: UIGestureRecognizerRepresentable {
        enum Direction { case left, right }

        let direction: Direction
        /// The finger's sideways distance, negative to the left.
        var changed: (CGFloat) -> Void
        /// Its distance and speed as it lifts; both zero if the swipe was cancelled.
        var ended: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

        func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

        func makeUIGestureRecognizer(context: Context) -> Recognizer {
            let pan = Recognizer()
            pan.delegate = context.coordinator
            pan.maximumNumberOfTouches = 1
            context.coordinator.direction = direction
            return pan
        }

        func updateUIGestureRecognizer(_ recognizer: Recognizer, context: Context) {
            context.coordinator.direction = direction
        }

        func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
            switch recognizer.state {
            case .began, .changed:
                changed(recognizer.translation(in: recognizer.view).x)
            case .ended:
                ended(recognizer.translation(in: recognizer.view).x, recognizer.velocity(in: recognizer.view).x)
            case .cancelled, .failed:
                ended(0, 0)
            default:
                break
            }
        }

        /// Its own class, so two of them never wait on each other.
        final class Recognizer: UIPanGestureRecognizer {}

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            var direction = Direction.right
            private var inSidewaysScroller = false

            func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
                // A wide table or code block scrolls sideways itself.
                var view = touch.view
                inSidewaysScroller = false
                while let current = view {
                    if let scroll = current as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 {
                        inSidewaysScroller = true
                        break
                    }
                    view = current.superview
                }
                return true
            }

            func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
                guard let pan = recognizer as? UIPanGestureRecognizer, !inSidewaysScroller else { return false }
                let velocity = pan.velocity(in: pan.view)
                guard abs(velocity.x) > abs(velocity.y) * 1.5 else { return false }
                return direction == .right ? velocity.x > 0 : velocity.x < 0
            }

            /// The conversation's scrolling and iOS's swipe back from anywhere in the chat wait to see
            /// whether this is a sideways swipe. The swipe back from the screen's edge doesn't.
            func gestureRecognizer(
                _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
            ) -> Bool {
                other is UIPanGestureRecognizer && !(other is UIScreenEdgePanGestureRecognizer)
                    && !(other is Recognizer)
            }
        }
    }

    /// A message pulled right far enough is replied to: an arrow shows behind it, and a tap of the
    /// haptics says letting go will reply.
    struct SwipeToReply: ViewModifier {
        let reply: () -> Void
        @State private var pull: CGFloat = 0
        @State private var armed = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        static let reach: CGFloat = 56

        func body(content: Content) -> some View {
            content
                .offset(x: pull)
                // Behind the message, where it started: the message slides off it. Only while
                // pulled, so VoiceOver doesn't find it; Reply is among the message's actions.
                .background(alignment: .leading) {
                    if pull > 0 {
                        let progress = min(1, pull / Self.reach)
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(armed ? Theme.ink : Theme.secondaryInk)
                            .frame(width: 32, height: 32)
                            .scaleEffect(0.6 + 0.4 * progress)
                            .opacity(progress)
                            .offset(x: pull / 2 - 16)
                            .accessibilityHidden(true)
                    }
                }
                .gesture(
                    SidewaysPan(direction: .right) { x in
                        armed = x >= Self.reach
                        pull = resisted(x, limit: Self.reach)
                    } ended: { x, _ in
                        if x >= Self.reach { reply() }
                        armed = false
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.2)) {
                            pull = 0
                        }
                    }
                )
                .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, armed in armed }
        }
    }

    extension TranscriptItem {
        /// What a swipe can reply to: someone's words, not a tool's.
        var swipesToReply: Bool {
            switch content {
            case .user, .assistant, .member: true
            default: false
            }
        }
    }

    /// Swipe to reply on the messages that can be replied to, in a conversation that replies.
    struct SwipeToReplyIfAble: ViewModifier {
        let item: TranscriptItem
        let actions: MessageActions?

        func body(content: Content) -> some View {
            if let actions, item.swipesToReply {
                content.modifier(SwipeToReply { actions.reply(item) })
            } else {
                content
            }
        }
    }
#endif
