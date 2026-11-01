import HermesKit
import SwiftUI

/// An agent's avatar: the picture it was given in the official app, or else its character on a soft
/// circle in the agent's colour.
struct AgentAvatar: View {
    let contact: Contact
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.botPictures) private var pictures

    var body: some View {
        let style = AvatarStyle(seed: contact.id, paletteCount: Theme.agentPalette.count)
        let tint = contact.tintColor(style: style)
        ZStack {
            Circle().fill(Theme.pane)
            if let picture = pictures?.data(for: contact.id).flatMap({ AvatarArt.picture($0, for: contact.id) }) {
                picture
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
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
        .accessibilityHidden(true)
    }
}

/// A working agent squashes and stretches gently, wherever its avatar shows.
private struct Breathing: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.phaseAnimator([false, true]) { view, up in
                view.scaleEffect(x: up ? 1.05 : 0.97, y: up ? 0.95 : 1.03, anchor: .bottom)
            } animation: { _ in
                .easeInOut(duration: 0.55)
            }
        } else {
            content
        }
    }
}

/// A room's avatar: two member avatars overlapping on a diagonal.
struct RoomAvatar: View {
    let members: [Contact]
    var size: CGFloat = 44

    var body: some View {
        let memberSize = size * 0.68
        ZStack(alignment: .topLeading) {
            if let first = members.first {
                AgentAvatar(contact: first.settled, size: memberSize)
            }
            if members.count > 1 {
                AgentAvatar(contact: members[1].settled, size: memberSize)
                    .background(Circle().fill(Theme.window).padding(-2))
                    .offset(x: size - memberSize, y: size - memberSize)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
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

    /// The agent's colour on your bubbles and the message box's main button, under white text.
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
