import SwiftUI

/// `.borderedProminent` (or `.glassProminent` on something floating) in the app's ink, with a label
/// that reads on it. SwiftUI draws a prominent button's label white, and in dark mode ink is near
/// white, so the label vanished.
struct InkProminentButtonStyle: PrimitiveButtonStyle {
    var glass = false

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if glass {
                Button(configuration).buttonStyle(.glassProminent)
            } else {
                Button(configuration).buttonStyle(.borderedProminent)
            }
        }
        .tint(Theme.primary)
        .foregroundStyle(Theme.primaryInk)
    }
}

extension PrimitiveButtonStyle where Self == InkProminentButtonStyle {
    /// The primary button in content: Sign In, New Routine, Connect.
    static var inkProminent: InkProminentButtonStyle { InkProminentButtonStyle() }
    /// The primary button floating over something, in glass.
    static var inkGlassProminent: InkProminentButtonStyle { InkProminentButtonStyle(glass: true) }
}
