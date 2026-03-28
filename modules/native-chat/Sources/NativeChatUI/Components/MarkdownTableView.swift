import ChatDomain
import ChatUIComponents
import ConversationSurfaceLogic
import SwiftUI

/// Renders a parsed Markdown table with wrapped columns and compact glass styling.
package struct MarkdownTableView: View {
    let table: MarkdownTable
    var filePathAnnotations: [FilePathAnnotation] = []
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?

    private var layout: MarkdownTableLayout {
        MarkdownTableLayout(table: table, idiom: UIDevice.current.userInterfaceIdiom)
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
                    cells: layout.paddedCells(for: table.headers),
                    isHeader: true
                )

                Divider()
                    .overlay(.white.opacity(0.08))

                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    tableRow(cells: layout.paddedCells(for: row), isHeader: false)
                        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.016) : .clear)

                    if index < table.rows.count - 1 {
                        Divider()
                            .overlay(.white.opacity(0.05))
                    }
                }
            }
            .frame(minWidth: layout.minimumTableWidth, alignment: .leading)
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
                    width: layout.columnWidths.indices.contains(index)
                        ? layout.columnWidths[index]
                        : layout.metrics.minimumColumnWidth,
                    alignment: frameAlignment(for: layout.alignment(forColumnAt: index)),
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
        alignment: Alignment,
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
            alignment: alignment
        )
        .padding(.horizontal, layout.metrics.horizontalCellPadding)
        .padding(.vertical, isHeader ? layout.metrics.headerVerticalPadding : layout.metrics.rowVerticalPadding)
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
}
