import ChatDomain
import Foundation
import SwiftUI
@preconcurrency import WebKit

/// A segment of inline content, either plain text or an inline LaTeX expression.
package enum InlineSegment {
    /// A plain text segment.
    case text(String)
    /// An inline LaTeX expression.
    case latexInline(String)
}

/// A block-level part of parsed Markdown content.
package enum BlockPart: Identifiable {
    case richText(id: Int, segments: [InlineSegment])
    case heading(id: Int, level: Int, text: String)
    case horizontalRule(id: Int)
    case latexBlock(id: Int, content: String)
    case codeBlock(id: Int, language: String?, code: String)

    /// Stable identifier for this block part.
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
        }
    }
}

// MARK: - Markdown Content View

/// Renders Markdown text with support for headings, code blocks, LaTeX, and inline formatting.
package struct MarkdownContentView: View {
    /// Controls whether the view renders with a glass bubble or as plain content.
    package enum SurfaceStyle {
        /// Renders without a surrounding bubble.
        case plain
        /// Renders inside an assistant glass bubble, with streaming-aware styling.
        case assistant(isLive: Bool)
    }

    let text: String
    var filePathAnnotations: [FilePathAnnotation] = []
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?
    var surfaceStyle: SurfaceStyle = .plain

    /// Creates a Markdown content view with the given text and optional annotations.
    package init(
        text: String,
        filePathAnnotations: [FilePathAnnotation] = [],
        onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)? = nil,
        surfaceStyle: SurfaceStyle = .plain
    ) {
        self.text = text
        self.filePathAnnotations = filePathAnnotations
        self.onSandboxLinkTap = onSandboxLinkTap
        self.surfaceStyle = surfaceStyle
    }

    var blockParts: [BlockPart] {
        parseBlocks(text)
    }

    /// The rendered Markdown block stack for the supplied text.
    package var body: some View {
        switch surfaceStyle {
        case .plain:
            blockStack(
                for: blockParts,
                codeBlockSurfaceStyle: .standalone
            )

        case let .assistant(isLive):
            blockStack(
                for: blockParts,
                codeBlockSurfaceStyle: .embedded
            )
            // Keep one logical assistant reply inside one outer bubble.
            .padding(12)
            .assistantSingleSurfaceGlass(isLive: isLive)
        }
    }

    func blockStack(
        for parts: [BlockPart],
        codeBlockSurfaceStyle: CodeBlockView.SurfaceStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(parts) { part in
                blockView(
                    for: part,
                    codeBlockSurfaceStyle: codeBlockSurfaceStyle
                )
            }
        }
    }

    @ViewBuilder
    func blockView(
        for part: BlockPart,
        codeBlockSurfaceStyle: CodeBlockView.SurfaceStyle
    ) -> some View {
        switch part {
        case let .codeBlock(id: id, language: language, code: code):
            CodeBlockView(
                language: language,
                code: code,
                surfaceStyle: codeBlockSurfaceStyle
            )
            .id(id)

        case let .horizontalRule(id: id):
            HorizontalRuleView()
                .id(id)

        case let .latexBlock(id: id, content: content):
            BlockLaTeXView(latex: content)
                .id(id)

        case let .heading(id: id, level: level, text: text):
            HeadingView(level: level, text: text)
                .id(id)

        case let .richText(id: id, segments: segments):
            RichTextView(
                segments: segments,
                filePathAnnotations: filePathAnnotations,
                onSandboxLinkTap: onSandboxLinkTap
            )
            .id(id)
        }
    }
}
