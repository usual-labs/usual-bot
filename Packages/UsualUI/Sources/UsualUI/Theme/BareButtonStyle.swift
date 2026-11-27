import SwiftUI

/// An icon with nothing behind it, for the message box's quiet buttons and the Mac's hover bar:
/// the glass around them read as a row of filled circles. `inset` keeps the spot a glass button
/// took, so the whole circle stays clickable.
struct BareButtonStyle: ButtonStyle {
    var inset: CGFloat = 0
    /// A grey circle behind the icon: the message box's secondary buttons on iPhone.
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        BareLabel(configuration: configuration, inset: inset, filled: filled)
    }

    private struct BareLabel: View {
        let configuration: Configuration
        let inset: CGFloat
        let filled: Bool
        @Environment(\.isEnabled) private var isEnabled
        /// A set colour, not `.fill`: that one follows the label's style, and a menu's label (Attach)
        /// came out darker than a button's.
        #if os(iOS)
            private static let fill = Color(uiColor: .secondarySystemFill)
        #else
            private static let fill = Color(nsColor: .quaternaryLabelColor)
        #endif

        var body: some View {
            configuration.label
                .padding(inset)
                .background { if filled { Circle().fill(Self.fill) } }
                .contentShape(Circle())
                .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
                .clickable()
        }
    }
}

extension ButtonStyle where Self == BareButtonStyle {
    static var bare: BareButtonStyle { BareButtonStyle() }
    static func bare(inset: CGFloat, filled: Bool = false) -> BareButtonStyle {
        BareButtonStyle(inset: inset, filled: filled)
    }
}
