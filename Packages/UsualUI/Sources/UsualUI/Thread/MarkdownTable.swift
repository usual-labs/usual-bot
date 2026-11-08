import Foundation
import SwiftUI

/// A Markdown table in a reply: a header row and the rows under it, every row as wide as the header.
struct MarkdownTable: Equatable {
    enum Alignment: Equatable { case leading, center, trailing }

    var alignments: [Alignment]
    var header: [AttributedString]
    var rows: [[AttributedString]] = []

    init(_ columns: [PresentationIntent.TableColumn]) {
        alignments = columns.map {
            switch $0.alignment {
            case .center: .center
            case .right: .trailing
            default: .leading
            }
        }
        header = Array(repeating: AttributedString(), count: columns.count)
    }

    /// Adds a run of the table's text to its cell. An empty cell has no run, so its place stays
    /// empty; a row that's new starts with its first run.
    mutating func add(_ text: AttributedString, row: Int?, newRow: Bool, column: Int) {
        guard alignments.indices.contains(column) else { return }
        if row == nil {
            header[column] += text
            return
        }
        if newRow || rows.isEmpty { rows.append(Array(repeating: AttributedString(), count: alignments.count)) }
        rows[rows.count - 1][column] += text
    }

    /// Each row as a line of its cells, for plain text: Select Text, search's excerpt, tests.
    var lines: [String] {
        ([header] + rows).map { $0.map { String($0.characters) }.joined(separator: "  ·  ") }
    }
}

/// A table in a reply: columns that line up, a bold header with a line under it, and faint lines
/// between rows. Long cells wrap; when the columns can't narrow enough to fit the message, the
/// table scrolls sideways and fades at the edge that has more.
struct MarkdownTableView: View {
    let table: MarkdownTable
    /// Gives a cell's bold, italic and code their fonts, as the rest of the reply.
    let styled: (AttributedString, Font.Weight) -> AttributedString
    @State private var moreToTheRight = false

    var body: some View {
        // The narrowest the columns go is the first form's ideal width, so it's picked whenever
        // wrapping makes the table fit, and the scrolling form only when it can't.
        ViewThatFits(in: .horizontal) {
            cells(TableLayout(columns: table.alignments.count, narrowestIsIdeal: true))
            ScrollView(.horizontal) {
                cells(TableLayout(columns: table.alignments.count, narrowestIsIdeal: false))
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.width - geometry.contentOffset.x - geometry.containerSize.width > 1
            } action: { _, more in
                moreToTheRight = more
            }
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: moreToTheRight ? 28 : 0)
                }
            }
        }
    }

    private func cells(_ layout: TableLayout) -> some View {
        let rows = [table.header] + table.rows
        return layout {
            ForEach(rows.indices, id: \.self) { row in
                ForEach(table.alignments.indices, id: \.self) { column in
                    cell(rows[row][column], row: row, column: column, isLastRow: row == rows.count - 1)
                }
            }
        }
    }

    private func cell(_ text: AttributedString, row: Int, column: Int, isLastRow: Bool) -> some View {
        let isHeader = row == 0
        let alignment = table.alignments[column]
        let header = String(table.header[column].characters)
        return Text(styled(text, isHeader ? .semibold : .regular))
            .fontWeight(isHeader ? .semibold : nil)
            .multilineTextAlignment(alignment.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
            // The gap between columns is inside each cell, so the lines under a row don't break.
            .padding(.trailing, column == table.alignments.count - 1 ? 0 : TableLayout.gap)
            .frame(
                maxWidth: .infinity, maxHeight: .infinity,
                alignment: Alignment(horizontal: alignment.frame, vertical: .top)
            )
            .overlay(alignment: .bottom) {
                if !isLastRow {
                    Rectangle()
                        .fill(isHeader ? Theme.secondaryInk.opacity(0.35) : Theme.border)
                        .frame(height: 1)
                }
            }
            // VoiceOver reads a cell with its column, as tables in other apps do.
            .accessibilityLabel(
                isHeader || header.isEmpty ? Text(text) : Text(verbatim: "\(header): \(String(text.characters))")
            )
            .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}

extension MarkdownTable.Alignment {
    fileprivate var text: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    fileprivate var frame: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// Lays a table's cells out in columns, row after row. Each column is as wide as its widest cell,
/// up to `widest`; offered less, wide columns give way first, down to `narrowest`.
struct TableLayout: Layout {
    let columns: Int
    /// With no width offered, answer the narrowest the table can be rather than its natural width.
    let narrowestIsIdeal: Bool

    static let widest: CGFloat = 280
    static let narrowest: CGFloat = 90
    static let gap: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = columnWidths(proposal.width, subviews)
        let heights = rowHeights(widths, subviews)
        return CGSize(width: widths.reduce(0, +), height: heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(bounds.width, subviews)
        let heights = rowHeights(widths, subviews)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            var x = bounds.minX
            for (column, width) in widths.enumerated() {
                subviews[row * columns + column].place(
                    at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: height))
                x += width
            }
            y += height
        }
    }

    private func columnWidths(_ offered: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        guard columns > 0 else { return [] }
        var ideal = Array(repeating: CGFloat(0), count: columns)
        for (index, cell) in subviews.enumerated() {
            ideal[index % columns] = max(ideal[index % columns], cell.sizeThatFits(.unspecified).width)
        }
        ideal = ideal.map { min($0, Self.widest).rounded(.up) }
        let minimum = ideal.map { min($0, Self.narrowest) }
        guard let offered, offered.isFinite else { return narrowestIsIdeal ? minimum : ideal }
        return Self.fitted(ideal: ideal, minimum: minimum, into: offered)
    }

    private func rowHeights(_ widths: [CGFloat], _ subviews: Subviews) -> [CGFloat] {
        guard columns > 0 else { return [] }
        return stride(from: 0, to: subviews.count, by: columns).map { start in
            (0..<min(columns, subviews.count - start)).map { column in
                subviews[start + column].sizeThatFits(ProposedViewSize(width: widths[column], height: nil)).height
            }.max() ?? 0
        }
    }

    /// Columns narrower than an even share of `width` keep their width; the rest split what's
    /// left evenly, but never below their minimum.
    static func fitted(ideal: [CGFloat], minimum: [CGFloat], into width: CGFloat) -> [CGFloat] {
        guard ideal.reduce(0, +) > width else { return ideal }
        var result = ideal
        var open = Set(ideal.indices)
        var remaining = width
        while !open.isEmpty {
            let share = remaining / CGFloat(open.count)
            let keeping = open.filter { ideal[$0] <= share }
            guard !keeping.isEmpty else {
                for index in open { result[index] = max(share.rounded(.down), minimum[index]) }
                break
            }
            for index in keeping {
                remaining -= ideal[index]
                open.remove(index)
            }
        }
        return result
    }
}
