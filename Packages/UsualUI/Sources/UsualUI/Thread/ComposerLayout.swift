import HermesKit
import SwiftUI

/// The message box's row of `+`, text and buttons. Expanded, it splits: the text takes the whole
/// width and the buttons move to a row of their own below it. One layout keeps each view's
/// identity, so the field keeps its focus and `+` its open picker as it changes.
struct ComposerLayout: Layout {
    var expanded: Bool
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 4

    enum Role { case leading, text, trailing }
    struct RoleKey: LayoutValueKey { static let defaultValue = Role.text }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = frames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, layout.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    /// Each subview's frame, in subview order, and the size they fill.
    private func frames(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let roles = subviews.map { $0[RoleKey.self] }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let side = { (role: Role) in zip(roles, ideal).first { $0.0 == role }?.1 ?? .zero }
        let leading = side(.leading)
        let trailing = side(.trailing)
        let hasLeading = roles.contains(.leading)
        let textWidth =
            expanded
            ? width
            : max(0, width - leading.width - trailing.width - spacing * CGFloat(roles.count - 1))
        let text =
            zip(roles, subviews).first { $0.0 == .text }?.1
            .sizeThatFits(ProposedViewSize(width: textWidth, height: nil)) ?? .zero
        if expanded {
            let row = max(leading.height, trailing.height)
            let height = text.height + rowSpacing + row
            let frames = roles.map { role -> CGRect in
                switch role {
                case .text: CGRect(x: 0, y: 0, width: width, height: text.height)
                case .leading:
                    CGRect(origin: CGPoint(x: 0, y: height - (row + leading.height) / 2), size: leading)
                case .trailing:
                    CGRect(
                        origin: CGPoint(x: width - trailing.width, y: height - (row + trailing.height) / 2),
                        size: trailing)
                }
            }
            return (frames, CGSize(width: width, height: height))
        }
        // One row, its parts on a shared bottom line.
        let height = max(leading.height, text.height, trailing.height)
        let textX = hasLeading ? leading.width + spacing : 0
        let frames = roles.map { role -> CGRect in
            switch role {
            case .leading: CGRect(origin: CGPoint(x: 0, y: height - leading.height), size: leading)
            case .text: CGRect(x: textX, y: height - text.height, width: textWidth, height: text.height)
            case .trailing:
                CGRect(
                    origin: CGPoint(x: width - trailing.width, y: height - trailing.height), size: trailing)
            }
        }
        return (frames, CGSize(width: width, height: height))
    }
}
