import HermesKit
import SwiftUI

/// An agent's avatar: the picture it was given in the official app, or else its character on a soft
/// circle in the agent's colour. The main Bot, Hermes, wears the app icon in place of a character.
/// `size` is at actual size; the Mac's zoom grows it. A working Bot breathes and wears a green
/// dot, one that needs you an amber dot.
struct AgentAvatar: View {
    let contact: Contact
    var size: CGFloat = 44
    /// Off where a badge has the corner, or the row around it already says the Bot is at work.
    var showsStatus = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.botPictures) private var pictures
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let size = Theme.zoomed(size, for: dynamicTypeSize)
        let style = AvatarStyle(seed: contact.id, paletteCount: Theme.agentPalette.count)
        let tint = contact.tintColor(style: style)
        ZStack {
            Circle().fill(Theme.pane)
            if let picture = pictures?.data(for: contact.id).flatMap({ AvatarArt.picture($0, for: contact.id) }) {
                picture
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else if contact.isMainBot {
                // The icon's framing (`scripts/make-app-icon.swift`): the drawing 104% wide on
                // white, 3% right of centre, its bust running 6% off the bottom. The rim, under the
                // drawing, keeps the white disc round on a white list in light mode.
                Circle().fill(.white)
                Circle().strokeBorder(Theme.border)
                HermesMark()
                    .scaleEffect(1.04)
                    .offset(x: 0.03 * size, y: 0.0626 * size)
            } else {
                Circle().fill(tint.opacity(0.28))
                if let art = AvatarArt.image(style.character) {
                    art
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        // The art keeps a transparent margin; fill more of the circle with the character.
                        .scaleEffect(1.15)
                }
            }
        }
        .clipShape(Circle())
        .frame(width: size, height: size)
        .modifier(Breathing(isActive: contact.activity == .working && !reduceMotion))
        .overlay(alignment: .bottomTrailing) {
            if showsStatus { StatusDot(activity: contact.activity, avatar: size) }
        }
        .accessibilityHidden(true)
    }
}

/// Green while a Bot works, amber while it needs you, on its avatar's rim at the bottom right. The
/// breathing alone was hard to see on small avatars. One dot, as a Bot is only ever one of these.
struct StatusDot: View {
    let activity: Contact.Activity
    /// The avatar's size as drawn.
    let avatar: CGFloat

    var body: some View {
        if let fill {
            let diameter = max(8, (avatar * 0.27).rounded())
            // On the circle's edge, which is this far in from the avatar's corner.
            let inward = avatar * 0.146 - diameter / 2
            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(Theme.window, lineWidth: avatar < 30 ? 1.5 : 2))
                .frame(width: diameter, height: diameter)
                .offset(x: -inward, y: -inward)
        }
    }

    private var fill: Color? {
        switch activity {
        case .idle: nil
        case .working: Theme.online
        case .needsYou: Theme.needsYouInk
        }
    }
}

/// A working agent squashes and stretches gently, wherever its avatar shows.
private struct Breathing: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            // Keyframes, not a phase animator: a phase animator changes phase inside an animated
            // transaction, which also animates the avatar's position. A chat that opens with its
            // agent at work would show the avatar sliding down from the top of the transcript.
            content.keyframeAnimator(initialValue: 0.0, repeating: true) { view, up in
                view.scaleEffect(x: 0.97 + 0.08 * up, y: 1.03 - 0.08 * up, anchor: .bottom)
            } keyframes: { _ in
                CubicKeyframe(1, duration: 0.55)
                CubicKeyframe(0, duration: 0.55)
            }
        } else {
            content
        }
    }
}

/// A room's avatar: two member avatars overlapping on a diagonal, with the room's dot on the
/// front one. The members never breathe: none of them is the one at work.
struct RoomAvatar: View {
    let members: [Contact]
    var size: CGFloat = 44
    var activity: Contact.Activity = .idle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The members' avatars zoom themselves, from their size at actual size.
        let memberSize = size * 0.68
        let shown = Theme.zoomed(size, for: dynamicTypeSize)
        let offset = shown - Theme.zoomed(memberSize, for: dynamicTypeSize)
        ZStack(alignment: .topLeading) {
            if let first = members.first {
                AgentAvatar(contact: first.settled, size: memberSize)
                    .overlay(alignment: .bottomTrailing) {
                        if members.count < 2 { StatusDot(activity: activity, avatar: shown - offset) }
                    }
            }
            if members.count > 1 {
                AgentAvatar(contact: members[1].settled, size: memberSize)
                    .background(Circle().fill(Theme.window).padding(-2))
                    .overlay(alignment: .bottomTrailing) { StatusDot(activity: activity, avatar: shown - offset) }
                    .offset(x: offset, y: offset)
            }
        }
        .frame(width: shown, height: shown, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// Agents' own pictures from the gateway; without them every agent shows its character.
    @Entry var botPictures: BotPictures?
    /// The agent this conversation is with; `nil` in rooms, which have no one colour or face.
    @Entry var chatContact: Contact?
}

extension Contact {
    func tintColor(style: AvatarStyle) -> Color {
        if let tint, let rgb = RGB(css: tint) { return Color(rgb) }
        return Theme.agentPalette[style.paletteIndex]
    }

    /// The agent's colour on the message box's main button, under white text.
    var accent: Color {
        let style = AvatarStyle(seed: id, paletteCount: Theme.agentColors.count)
        let rgb = tint.flatMap(RGB.init(css:)) ?? Theme.agentColors[style.paletteIndex]
        return Color(rgb.readableUnderWhite)
    }

    /// Member avatars inside a room never show their own activity.
    fileprivate var settled: Contact { with(activity: .idle) }

    func with(activity: Activity) -> Contact {
        var copy = self
        copy.activity = activity
        return copy
    }
}
