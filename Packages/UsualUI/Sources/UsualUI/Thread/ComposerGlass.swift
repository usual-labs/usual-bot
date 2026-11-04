import SwiftUI

/// A symbol in one of the message box's round buttons, which are `composerButtonSize` across.
struct ComposerGlyph: View {
    let systemImage: String
    /// The symbol's size in a 28 pt button.
    var scale: CGFloat = 13
    var weight: Font.Weight = .semibold
    /// Send or a call: on the Bot's colour (ink in a room) rather than clear glass.
    var prominent = false
    @Environment(\.composerButtonSize) private var size
    @Environment(\.chatContact) private var contact

    var body: some View {
        let side = size - ComposerGlass.inset * 2
        Image(systemName: systemImage)
            .font(.system(size: size * scale / 28, weight: weight))
            .foregroundStyle(prominent ? (contact == nil ? Theme.primaryInk : Theme.userBubbleInk) : Theme.ink)
            .frame(width: side, height: side)
    }
}

/// The message box's round buttons are the system's Liquid Glass circles. The prominent one, Send
/// or a call, is tinted with the Bot's colour, or ink in a room. Like any tinted glass, macOS draws
/// it grey while its window isn't the one you're at.
struct ComposerGlass: ViewModifier {
    /// What the glass styles draw around a label, so a button comes out `composerButtonSize` across.
    #if os(iOS)
        static let inset: CGFloat = 7
    #else
        static let inset: CGFloat = 4
    #endif
    let prominent: Bool
    @Environment(\.chatContact) private var contact

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent).tint(contact?.accent ?? Theme.primary).buttonBorderShape(.circle)
        } else {
            content.buttonStyle(.glass).buttonBorderShape(.circle)
        }
    }
}

extension View {
    /// A round Liquid Glass button in the message box; `prominent` for Send and a call.
    func composerGlass(prominent: Bool = false) -> some View {
        modifier(ComposerGlass(prominent: prominent))
    }
}
