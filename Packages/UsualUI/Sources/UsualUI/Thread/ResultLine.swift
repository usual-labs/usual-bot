import SwiftUI

/// Work Hermes finished on its own, as one line with the report a click away. Nobody wrote it, so
/// it isn't a bubble and has no message actions.
struct ResultLine: View {
    let title: String
    let detail: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if detail.isEmpty {
                label
            } else {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { expanded.toggle() }
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
            }
            if expanded {
                report
                    .frame(maxWidth: Theme.bubbleWidth, alignment: .leading)
                    .background(Theme.codeFill, in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 12))
                .accessibilityHidden(true)
            Text(title).lineLimit(1)
            if !detail.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.secondaryInk)
        .padding(.leading, 12)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    /// Short reports show whole; long ones scroll inside a fixed height.
    private var report: some View {
        let text = Text(detail)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        return ViewThatFits(in: .vertical) {
            text
            ScrollView { text }
        }
        .frame(maxHeight: 320)
    }
}
