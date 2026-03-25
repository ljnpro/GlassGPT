import ChatDomain
import ChatUIComponents
import SwiftUI

/// Renders a parsed Markdown table with compact glass styling.
package struct MarkdownTableView: View {
    let table: MarkdownTable
    var filePathAnnotations: [FilePathAnnotation] = []
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?

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
                    cells: table.headers,
                    isHeader: true
                )

                Divider()
                    .overlay(.white.opacity(0.08))

                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    tableRow(cells: row, isHeader: false)
                        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.01) : .clear)

                    if index < table.rows.count - 1 {
                        Divider()
                            .overlay(.white.opacity(0.05))
                    }
                }
            }
            .padding(1)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.03))
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
                RichTextView(
                    segments: cell,
                    filePathAnnotations: filePathAnnotations,
                    onSandboxLinkTap: onSandboxLinkTap
                )
                .font(isHeader ? .caption.weight(.semibold) : .caption)
                .frame(
                    minWidth: 120,
                    alignment: frameAlignment(for: table.alignments[safe: index] ?? .leading)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, isHeader ? 8 : 7)

                if index < cells.count - 1 {
                    Divider()
                        .overlay(.white.opacity(0.05))
                }
            }
        }
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

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
