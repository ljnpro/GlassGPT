import Foundation

/// A segment of inline content, either plain text or an inline LaTeX expression.
package enum InlineSegment: Equatable {
    case text(String)
    case latexInline(String)
}

/// Horizontal alignment for one parsed Markdown table column.
package enum MarkdownTableAlignment: Equatable {
    case leading
    case center
    case trailing
}

/// A parsed pipe-table extracted from Markdown block content.
package struct MarkdownTable: Equatable {
    package let headers: [[InlineSegment]]
    package let rows: [[[InlineSegment]]]
    package let alignments: [MarkdownTableAlignment]

    /// Creates a parsed Markdown table model from headers, rows, and alignment metadata.
    package init(
        headers: [[InlineSegment]],
        rows: [[[InlineSegment]]],
        alignments: [MarkdownTableAlignment]
    ) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
    }
}

/// A block-level part of parsed Markdown content.
package enum BlockPart: Identifiable {
    case richText(id: Int, segments: [InlineSegment])
    case heading(id: Int, level: Int, text: String)
    case horizontalRule(id: Int)
    case latexBlock(id: Int, content: String)
    case codeBlock(id: Int, language: String?, code: String)
    case table(id: Int, table: MarkdownTable)

    package var id: Int {
        switch self {
        case let .richText(id, _):
            id
        case let .heading(id, _, _):
            id
        case let .horizontalRule(id):
            id
        case let .latexBlock(id, _):
            id
        case let .codeBlock(id, _, _):
            id
        case let .table(id, _):
            id
        }
    }
}
