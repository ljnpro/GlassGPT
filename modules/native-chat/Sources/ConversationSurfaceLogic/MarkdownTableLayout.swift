import CoreGraphics
import UIKit

/// Computes stable layout metrics and column widths for rendered Markdown tables.
package struct MarkdownTableLayout {
    /// Device-adaptive sizing metrics used when laying out a Markdown table.
    package struct Metrics {
        package let minimumColumnWidth: CGFloat
        package let maximumColumnWidth: CGFloat
        package let horizontalCellPadding: CGFloat
        package let headerVerticalPadding: CGFloat
        package let rowVerticalPadding: CGFloat
        package let characterWidth: CGFloat
        package let minimumCharacterCount: Int

        init(idiom: UIUserInterfaceIdiom) {
            switch idiom {
            case .pad:
                minimumColumnWidth = 132
                maximumColumnWidth = 260
                horizontalCellPadding = 12
                headerVerticalPadding = 10
                rowVerticalPadding = 8
                characterWidth = 7.6
                minimumCharacterCount = 10
            default:
                minimumColumnWidth = 104
                maximumColumnWidth = 210
                horizontalCellPadding = 9
                headerVerticalPadding = 8
                rowVerticalPadding = 7
                characterWidth = 6.6
                minimumCharacterCount = 9
            }
        }
    }

    package let columnWidths: [CGFloat]
    package let minimumTableWidth: CGFloat
    package let metrics: Metrics
    private let alignments: [MarkdownTableAlignment]

    /// Creates a table layout from one parsed table and the current device idiom.
    package init(table: MarkdownTable, idiom: UIUserInterfaceIdiom) {
        let metrics = Metrics(idiom: idiom)
        self.metrics = metrics
        alignments = table.alignments

        let allRows = [table.headers] + table.rows
        let columnCount = max(
            table.headers.count,
            table.rows.map(\.count).max() ?? 0
        )

        if columnCount == 0 {
            columnWidths = []
            minimumTableWidth = 0
            return
        }

        columnWidths = (0 ..< columnCount).map { columnIndex in
            let cellLengths = allRows.compactMap { row -> Int? in
                guard row.indices.contains(columnIndex) else { return nil }
                return Self.textLength(for: row[columnIndex])
            }

            let longestLength = max(cellLengths.max() ?? 0, metrics.minimumCharacterCount)
            let estimatedWidth = CGFloat(longestLength) * metrics.characterWidth
            return min(max(estimatedWidth, metrics.minimumColumnWidth), metrics.maximumColumnWidth)
        }

        let dividerWidth = CGFloat(max(columnWidths.count - 1, 0))
        minimumTableWidth = columnWidths.reduce(0, +) + dividerWidth
    }

    /// Pads a short row with empty cells so it matches the computed table width.
    package func paddedCells(for row: [[InlineSegment]]) -> [[InlineSegment]] {
        guard row.count < columnWidths.count else {
            return row
        }

        return row + Array(repeating: [.text("")], count: columnWidths.count - row.count)
    }

    /// Returns the text alignment that should be used for one column.
    package func alignment(forColumnAt index: Int) -> MarkdownTableAlignment {
        alignments[safe: index] ?? .leading
    }

    package static func textLength(for segments: [InlineSegment]) -> Int {
        let combined = segments.map { segment in
            switch segment {
            case let .text(text):
                text
            case let .latexInline(latex):
                latex
            }
        }
        .joined()
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return min(max(combined.count, 0), 80)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
