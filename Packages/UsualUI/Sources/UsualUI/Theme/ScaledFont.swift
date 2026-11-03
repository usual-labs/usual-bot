import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// The app sets its type in points, tuned at the default text size. On iPhone those sizes follow
/// Dynamic Type the way the nearest text style would, so 17 pt grows like body and 13 pt like
/// footnote. The Mac has no Dynamic Type and keeps its sizes.
extension Theme {
    static func scaled(_ size: CGFloat, for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        #if os(iOS)
            guard dynamicTypeSize != .large else { return size }
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
            return UIFontMetrics(forTextStyle: textStyle(for: size)).scaledValue(for: size, compatibleWith: traits)
        #else
            return size
        #endif
    }

    #if os(iOS)
        /// The text style whose default size is nearest, so small print grows less than body text,
        /// as it does in Apple's apps.
        private static func textStyle(for size: CGFloat) -> UIFont.TextStyle {
            switch size {
            case ..<11.5: .caption2
            case ..<12.5: .caption1
            case ..<14: .footnote
            case ..<15.5: .subheadline
            case ..<16.5: .callout
            case ..<18.5: .body
            case ..<21: .title3
            case ..<25: .title2
            case ..<31: .title1
            default: .largeTitle
            }
        }
    #endif
}

extension Font {
    /// A system font at `size` points at the default text size, scaled for `dynamicTypeSize`. For
    /// places that need a `Font` rather than a view, such as text runs; views use `scaledFont`.
    static func scaled(
        _ size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil, for dynamicTypeSize: DynamicTypeSize
    ) -> Font {
        .system(size: Theme.scaled(size, for: dynamicTypeSize), weight: weight, design: design)
    }
}

extension View {
    /// Sets a system font of `size` points at the default text size, growing with Dynamic Type on
    /// iPhone. Use it in place of `.font(.system(size:))`. To keep a control from growing past a
    /// point, cap it from outside with `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`.
    public func scaledFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

private struct ScaledFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(.scaled(size, weight: weight, design: design, for: dynamicTypeSize))
    }
}

extension View {
    /// At most `lines`, or `accessibilityLines` at accessibility text sizes, where one line holds
    /// only a word or two.
    func lineLimit(_ lines: Int, accessibility accessibilityLines: Int) -> some View {
        modifier(GrowingLineLimit(lines: lines, accessibilityLines: accessibilityLines))
    }
}

private struct GrowingLineLimit: ViewModifier {
    let lines: Int
    let accessibilityLines: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.lineLimit(dynamicTypeSize.isAccessibilitySize ? accessibilityLines : lines)
    }
}
