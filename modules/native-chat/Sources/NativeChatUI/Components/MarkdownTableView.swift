import ChatDomain
import ChatUIComponents
import SwiftUI

/// Renders a parsed Markdown table with wrapped columns and compact glass styling.
package struct MarkdownTableView: View {
    let table: MarkdownTable
    var filePathAnnotations: [FilePathAnnotation] = []
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?

    private var metrics: Metrics {
        .init(idiom: UIDevice.current.userInterfaceIdiom)
    }

    private var columnWidths: [CGFloat] {
        let columnCount = max(
            table.headers.count,
            table.rows.map(\.count).max() ?? 0
        )

        guard columnCount > 0 else {
            return []
        }

        return (0 ..< columnCount).map { columnIndex in
            let cellLengths = allRows.compactMap { row -> Int? in
                guard row.indices.contains(columnIndex) else { return nil }
                return textLength(for: row[columnIndex])
            }

            let longestLength = max(cellLengths.max() ?? 0, metrics.minimumCharacterCount)
            let estimatedWidth = CGFloat(longestLength) * metrics.characterWidth
            return min(max(estimatedWidth, metrics.minimumColumnWidth), metrics.maximumColumnWidth)
        }
    }

    private var minimumTableWidth: CGFloat {
        let dividerWidth = CGFloat(max(columnWidths.count - 1, 0))
        return columnWidths.reduce(0, +) + dividerWidth
    }

    private var allRows: [[[InlineSegment]]] {
        [table.headers] + table.rows
    }

    /// Creates a table view for the supplied parsed Markdown table.
    package init(
        table: MarkdownTable,
        filePathAnnotations: [FilePathAnnotation] = [],
        onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)? = nil
    ) {
        self.table = table
        self.filePathAnnotations = filePathAnnotations
        self.onSandboxLinkTap = onSandboxLinkTap
    }

    /// The horizontally scrollable rendered table body.
    package var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(
                    cells: paddedCells(for: table.headers),
                    isHeader: true
                )

                Divider()
                    .overlay(.white.opacity(0.08))

                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    tableRow(cells: paddedCells(for: row), isHeader: false)
                        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.016) : .clear)

                    if index < table.rows.count - 1 {
                        Divider()
                            .overlay(.white.opacity(0.05))
                    }
                }
            }
            .frame(minWidth: minimumTableWidth, alignment: .leading)
            .padding(1)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.75)
            )
        }
    }

    private func tableRow(
        cells: [[InlineSegment]],
        isHeader: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                tableCell(
                    cell,
                    width: columnWidths[safe: index] ?? metrics.minimumColumnWidth,
                    alignment: table.alignments[safe: index] ?? .leading,
                    isHeader: isHeader
                )

                if index < cells.count - 1 {
                    Divider()
                        .overlay(.white.opacity(0.05))
                }
            }
        }
        .background(isHeader ? Color.white.opacity(0.05) : .clear)
    }

    private func tableCell(
        _ segments: [InlineSegment],
        width: CGFloat,
        alignment: MarkdownTableAlignment,
        isHeader: Bool
    ) -> some View {
        RichTextView(
            segments: segments,
            filePathAnnotations: filePathAnnotations,
            onSandboxLinkTap: onSandboxLinkTap
        )
        .font(isHeader ? .caption.weight(.semibold) : .caption)
        .lineSpacing(isHeader ? 2 : 1)
        .frame(
            width: width,
            alignment: frameAlignment(for: alignment)
        )
        .padding(.horizontal, metrics.horizontalCellPadding)
        .padding(.vertical, isHeader ? metrics.headerVerticalPadding : metrics.rowVerticalPadding)
    }

    private func frameAlignment(for alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .leading:
            .leading
        case .center:
            .center
        case .trailing:
            .trailing
        }
    }

    private func paddedCells(for row: [[InlineSegment]]) -> [[InlineSegment]] {
        guard row.count < columnWidths.count else {
            return row
        }

        return row + Array(repeating: [.text("")], count: columnWidths.count - row.count)
    }

    private func textLength(for segments: [InlineSegment]) -> Int {
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

private extension MarkdownTableView {
    struct Metrics {
        let minimumColumnWidth: CGFloat
        let maximumColumnWidth: CGFloat
        let horizontalCellPadding: CGFloat
        let headerVerticalPadding: CGFloat
        let rowVerticalPadding: CGFloat
        let characterWidth: CGFloat
        let minimumCharacterCount: Int

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
}
