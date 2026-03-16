import SwiftUI
import Foundation
@preconcurrency import WebKit

enum InlineSegment: Sendable {
    case text(String)
    case latexInline(String)
}

enum BlockPart: Identifiable, Sendable {
    case richText(id: Int, segments: [InlineSegment])
    case heading(id: Int, level: Int, text: String)
    case horizontalRule(id: Int)
    case latexBlock(id: Int, content: String)
    case codeBlock(id: Int, language: String?, code: String)

    var id: Int {
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

struct MarkdownContentView: View {
    enum SurfaceStyle {
        case plain
        case assistant(isLive: Bool)
    }

    let text: String
    var filePathAnnotations: [FilePathAnnotation] = []
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?
    var surfaceStyle: SurfaceStyle = .plain

    var blockParts: [BlockPart] {
        parseBlocks(text)
    }

    var normalizedAssistantBlockParts: [BlockPart] {
        splitAssistantRichTextParts(blockParts)
    }

    var shouldUseSegmentedAssistantSurface: Bool {
        normalizedAssistantBlockParts.contains { part in
            switch part {
            case .codeBlock, .latexBlock:
                return true
            default:
                return false
            }
        } || normalizedAssistantBlockParts.count > 4 || text.count > 900
    }

    var assistantSurfaceSections: [AssistantSurfaceSection] {
        var sections: [AssistantSurfaceSection] = []
        var currentParts: [BlockPart] = []
        var currentWeight = 0

        func flushCurrentParts() {
            guard !currentParts.isEmpty else { return }
            sections.append(
                AssistantSurfaceSection(
                    id: currentParts[0].id,
                    presentation: .content(parts: currentParts)
                )
            )
            currentParts = []
            currentWeight = 0
        }

        for part in normalizedAssistantBlockParts {
            switch part {
            case let .codeBlock(_, language, code):
                flushCurrentParts()
                sections.append(
                    AssistantSurfaceSection(
                        id: part.id,
                        presentation: .code(language: language, code: code)
                    )
                )
            case let .latexBlock(_, content):
                flushCurrentParts()
                sections.append(
                    AssistantSurfaceSection(
                        id: part.id,
                        presentation: .latex(content: content)
                    )
                )
            default:
                if part.startsAssistantSection, !currentParts.isEmpty {
                    flushCurrentParts()
                }

                let weight = part.assistantGroupingWeight
                let shouldSplit = !currentParts.isEmpty && (
                    currentParts.count >= 2 || currentWeight + weight > 5
                )

                if shouldSplit {
                    flushCurrentParts()
                }

                currentParts.append(part)
                currentWeight += weight
            }
        }

        flushCurrentParts()
        return sections.isEmpty
            ? [AssistantSurfaceSection(id: 0, presentation: .content(parts: normalizedAssistantBlockParts))]
            : sections
    }

    var body: some View {
        switch surfaceStyle {
        case .plain:
            blockStack(
                for: blockParts,
                codeBlockSurfaceStyle: .standalone
            )

        case .assistant(let isLive):
            if shouldUseSegmentedAssistantSurface {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(assistantSurfaceSections) { section in
                        assistantSurfaceView(section, isLive: isLive)
                    }
                }
            } else {
                blockStack(
                    for: blockParts,
                    codeBlockSurfaceStyle: .embedded
                )
                .padding(12)
                .assistantSingleSurfaceGlass(isLive: isLive)
            }
        }
    }

    @ViewBuilder
    func assistantSurfaceView(_ section: AssistantSurfaceSection, isLive: Bool) -> some View {
        switch section.presentation {
        case let .content(parts):
            blockStack(
                for: parts,
                codeBlockSurfaceStyle: .embedded
            )
            .padding(section.contentPadding)
            .assistantSingleSurfaceGlass(isLive: isLive)

        case let .code(language, code):
            CodeBlockView(
                language: language,
                code: code,
                surfaceStyle: .standalone
            )

        case let .latex(content):
            StandaloneBlockLaTeXCardView(latex: content)
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
