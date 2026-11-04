import SwiftUI

/// `.borderedProminent` (or `.glassProminent` on something floating) in the app's ink, with a label
/// that reads on it. SwiftUI draws a prominent button's label white, and in dark mode ink is near
/// white, so the label vanished. iPhone takes ink's own contrast colour for the label. The Mac
/// can't: a window in the background draws the button unfilled in its label colour, so there the
/// fill turns grey in dark mode and the label stays white (6:1).
struct InkProminentButtonStyle: PrimitiveButtonStyle {
    var glass = false

    func makeBody(configuration: Configuration) -> some View {
        let button = Group {
            if glass {
                Button(configuration).buttonStyle(.glassProminent)
            } else {
                Button(configuration).buttonStyle(.borderedProminent)
            }
        }
        #if os(iOS)
            return button.tint(Theme.primary).foregroundStyle(Theme.primaryInk)
        #else
            return button.tint(Theme.prominent)
        #endif
    }
}

extension PrimitiveButtonStyle where Self == InkProminentButtonStyle {
    /// The primary button in content: Sign In, New Routine, Allow once.
    static var inkProminent: InkProminentButtonStyle { InkProminentButtonStyle() }
    /// The primary button floating over something, in glass.
    static var inkGlassProminent: InkProminentButtonStyle { InkProminentButtonStyle(glass: true) }
}

extension Theme {
    /// A Mac prominent button's fill: ink, and in dark mode a grey white text reads on.
    static let prominent = Color(light: 0x1C1C1C, dark: 0x636366)
}
