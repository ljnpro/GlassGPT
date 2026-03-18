import ChatDomain
import SwiftUI
import Foundation
@preconcurrency import WebKit

package enum InlineSegment: Sendable {
    case text(String)
    case latexInline(String)
}

package enum BlockPart: Identifiable, Sendable {
    case richText(id: Int, segments: [InlineSegment])
    case heading(id: Int, level: Int, text: String)
    case horizontalRule(id: Int)
    case latexBlock(id: Int, content: String)
    case codeBlock(id: Int, language: String?, code: String)

    package var id: Int {
        switch self {
        case let .richText(id, _):
            return id
        case let .heading(id, _, _):
            return id
        case let .horizontalRule(id):
            return id
        case let .latexBlock(id, _):
            return id
        case let .codeBlock(id, _, _):
            return id
        }
    }
}

// MARK: - Markdown Content View

package struct MarkdownContentView: View {
    package enum SurfaceStyle {
        case plain
        case assistant(isLive: Bool)
    }

    let text: String
    var filePathAnnotations: [FilePathAnnotation] = []
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?
    var surfaceStyle: SurfaceStyle = .plain

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

    package var body: some View {
        switch surfaceStyle {
        case .plain:
            blockStack(
                for: blockParts,
                codeBlockSurfaceStyle: .standalone
            )

        case .assistant(let isLive):
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
