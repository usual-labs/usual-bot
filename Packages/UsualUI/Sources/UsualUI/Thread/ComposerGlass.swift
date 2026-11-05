import SwiftUI

/// A symbol in one of the message box's round buttons, which are `composerButtonSize` across.
struct ComposerGlyph: View {
    let systemImage: String
    /// The symbol's size in a 28 pt button.
    var scale: CGFloat = 13
    var weight: Font.Weight = .semibold
    /// Send or a call: on the Bot's colour (ink in a room) rather than a bare icon.
    var prominent = false
    @Environment(\.composerButtonSize) private var size
    @Environment(\.chatContact) private var contact

    var body: some View {
        let side = size - ComposerGlass.inset * 2
        Image(systemName: systemImage)
            .font(.system(size: size * scale / 28, weight: weight))
            .foregroundStyle(prominent ? (contact == nil ? Theme.primaryInk : Theme.userBubbleInk) : Theme.secondaryInk)
            .frame(width: side, height: side)
    }
}

/// The message box's round buttons. The prominent one, Send or a call, is a Liquid Glass circle
/// tinted with the Bot's colour, or ink in a room; like any tinted glass, macOS draws it grey while
/// its window isn't the one you're at. The rest are bare icons in the same spot, as in Grok's app.
struct ComposerGlass: ViewModifier {
    /// What the glass style draws around a label, so a button comes out `composerButtonSize` across.
    #if os(iOS)
        static let inset: CGFloat = 7
    #else
        static let inset: CGFloat = 4
    #endif
    let prominent: Bool
    @Environment(\.chatContact) private var contact

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.clickable(.glassProminent)).tint(contact?.accent ?? Theme.primary).buttonBorderShape(
                .circle)
        } else {
            content.buttonStyle(.bare(inset: Self.inset))
        }
    }
}

extension View {
    /// A round button in the message box: glass in the Bot's colour if `prominent` (Send and a
    /// call), a bare icon otherwise.
    func composerGlass(prominent: Bool = false) -> some View {
        modifier(ComposerGlass(prominent: prominent))
    }
}
