import SwiftUI

/// An icon with nothing behind it, for the message box's quiet buttons and the Mac's hover bar:
/// the glass around them read as a row of filled circles. `inset` keeps the spot a glass button
/// took, so the whole circle stays clickable.
struct BareButtonStyle: ButtonStyle {
    var inset: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        BareLabel(configuration: configuration, inset: inset)
    }

    private struct BareLabel: View {
        let configuration: Configuration
        let inset: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(inset)
                .contentShape(Circle())
                .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.6 : 1)
                .clickable()
        }
    }
}

extension ButtonStyle where Self == BareButtonStyle {
    static var bare: BareButtonStyle { BareButtonStyle() }
    static func bare(inset: CGFloat) -> BareButtonStyle { BareButtonStyle(inset: inset) }
}
