import SwiftUI

extension View {
    /// The pointing hand on the Mac over anything that answers a click, so you can tell what does.
    /// The plain arrow stays while it's disabled. iPhone has no pointer to change.
    public func clickable() -> some View {
        modifier(Clickable())
    }
}

extension View {
    /// On iPhone, a hit area at least 44 pt each way around a control drawn `width` by `height`,
    /// without moving anything: the extra spills over what's around it. Use inside a button's
    /// label, after its frame. The Mac keeps its pointer-sized targets.
    func touchTarget(width: CGFloat, height: CGFloat) -> some View {
        #if os(iOS)
            let dx = max(0, 44 - width) / 2
            let dy = max(0, 44 - height) / 2
            return padding(.horizontal, dx).padding(.vertical, dy).contentShape(Rectangle())
                .padding(.horizontal, -dx).padding(.vertical, -dy)
        #else
            return self
        #endif
    }
}

private struct Clickable: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        #if os(macOS)
            content.pointerStyle(isEnabled ? .link : nil)
        #else
            content
        #endif
    }
}

/// A button style with the pointing hand on the Mac: `.clickable` is `.plain`, and
/// `.clickable(.bordered)` wraps any other style. Like any style it reaches every button inside
/// what it's set on, so `RootView` sets `.clickable(.automatic)` for buttons that pick no style.
public struct ClickableButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    let base: Base

    public func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
            ZoomedButton(configuration: configuration, zooms: Self.drawsOwnLabel).buttonStyle(base).clickable()
        #else
            Button(configuration).buttonStyle(base).clickable()
        #endif
    }

    /// The Mac's bordered buttons set their label's font themselves, whatever the window's font.
    private static var drawsOwnLabel: Bool {
        Base.self == BorderedButtonStyle.self || Base.self == BorderedProminentButtonStyle.self
            || Base.self == DefaultButtonStyle.self
    }
}

#if os(macOS)
    /// A bordered button's label at the window's zoom. The Mac's bordered buttons ignore the font
    /// around them and set their label's for their control size, so a zoomed window gives the label
    /// a font of its own. At actual size the button is left as it was made.
    struct ZoomedButton: View {
        let configuration: PrimitiveButtonStyleConfiguration
        let zooms: Bool
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.controlSize) private var controlSize

        var body: some View {
            if zooms, dynamicTypeSize != .large {
                Button(role: configuration.role, action: configuration.trigger) {
                    configuration.label.font(.system(size: labelSize * Zoom.factor(dynamicTypeSize)))
                }
            } else {
                Button(configuration)
            }
        }

        /// The size each control size gives its label at actual size.
        private var labelSize: CGFloat {
            switch controlSize {
            case .mini: 9
            case .small: 11
            case .extraLarge: 15
            default: 13
            }
        }
    }
#endif

extension PrimitiveButtonStyle where Self == ClickableButtonStyle<PlainButtonStyle> {
    public static var clickable: Self { ClickableButtonStyle(base: .plain) }
}

extension PrimitiveButtonStyle {
    public static func clickable<Base: PrimitiveButtonStyle>(_ base: Base) -> Self
    where Self == ClickableButtonStyle<Base> {
        ClickableButtonStyle(base: base)
    }
}
