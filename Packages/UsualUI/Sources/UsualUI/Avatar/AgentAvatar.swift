import HermesKit
import SwiftUI

/// An agent's avatar: a solid circle in the agent's colour with one white dot.
struct AgentAvatar: View {
    let contact: Contact
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let style = AvatarStyle(seed: contact.id, paletteCount: Theme.agentPalette.count)
        let dotSize = size * 0.23
        ZStack(alignment: .topLeading) {
            Circle().fill(contact.tintColor(style: style))
            Circle()
                .fill(.white)
                .frame(width: dotSize, height: dotSize)
                .offset(x: style.dot.x * size - dotSize / 2, y: style.dot.y * size - dotSize / 2)
        }
        .frame(width: size, height: size)
        .overlay {
            if contact.activity == .working {
                Circle()
                    .stroke(contact.tintColor(style: style), lineWidth: 2)
                    .padding(-4)
                    .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.35))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse
                    )
                    .onAppear { pulse = true }
            }
        }
        .accessibilityHidden(true)
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

extension Contact {
    func tintColor(style: AvatarStyle) -> Color {
        if let tint, let rgb = RGB(css: tint) { return Color(rgb) }
        return Theme.agentPalette[style.paletteIndex]
    }

    /// Member avatars inside a room never show their own activity ring.
    fileprivate var settled: Contact {
        var copy = self
        copy.activity = .idle
        return copy
    }
}
