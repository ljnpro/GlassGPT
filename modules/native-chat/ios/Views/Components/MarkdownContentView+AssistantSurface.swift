import SwiftUI

struct AssistantSurfaceSection: Identifiable {
    enum Presentation {
        case content(parts: [BlockPart])
        case code(language: String?, code: String)
        case latex(content: String)
    }

    let id: Int
    let presentation: Presentation

    var contentPadding: EdgeInsets {
        switch presentation {
        case let .content(parts):
            if parts.count == 1 {
                switch parts[0] {
                case .heading:
                    return EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12)
                default:
                    break
                }
            }

            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        case .code, .latex:
            return EdgeInsets()
        }
    }
}

extension BlockPart {
    var assistantGroupingWeight: Int {
        switch self {
        case let .richText(_, segments):
            let length = segments.reduce(into: 0) { partialResult, segment in
                switch segment {
                case let .text(text):
                    partialResult += text.count
                case let .latexInline(latex):
                    partialResult += latex.count + 2
                }
            }
            return min(max((length / 220) + 1, 1), 4)
        case .heading:
            return 2
        case .horizontalRule:
            return 1
        case .codeBlock, .latexBlock:
            return 6
        }
    }

    var startsAssistantSection: Bool {
        switch self {
        case .heading:
            return true
        default:
            return false
        }
    }
}

extension MarkdownContentView {
    func splitAssistantRichTextParts(_ parts: [BlockPart]) -> [BlockPart] {
        var nextID = 0

        func makeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        func rebuiltPart(_ part: BlockPart) -> BlockPart {
            switch part {
            case let .heading(_, level, text):
                return .heading(id: makeID(), level: level, text: text)
            case .horizontalRule:
                return .horizontalRule(id: makeID())
            case let .latexBlock(_, content):
                return .latexBlock(id: makeID(), content: content)
            case let .codeBlock(_, language, code):
                return .codeBlock(id: makeID(), language: language, code: code)
            case let .richText(_, segments):
                return .richText(id: makeID(), segments: segments)
            }
        }

        func rebuildInlineText(from segments: [InlineSegment]) -> String {
            segments.map { segment in
                switch segment {
                case let .text(text):
                    return text
                case let .latexInline(latex):
                    return "$\(latex)$"
                }
            }
            .joined()
        }

        func splitParagraphs(in text: String) -> [String] {
            var paragraphs: [String] = []
            var currentLines: [String] = []

            func flushCurrentLines() {
                let paragraph = currentLines
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !paragraph.isEmpty {
                    paragraphs.append(paragraph)
                }
                currentLines = []
            }

            for line in text.components(separatedBy: "\n") {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    flushCurrentLines()
                } else {
                    currentLines.append(line)
                }
            }

            flushCurrentLines()
            return paragraphs
        }

        var normalized: [BlockPart] = []

        for part in parts {
            switch part {
            case let .richText(_, segments):
                let rawText = rebuildInlineText(from: segments)
                let paragraphs = splitParagraphs(in: rawText)

                if paragraphs.count <= 1 {
                    normalized.append(rebuiltPart(part))
                } else {
                    for paragraph in paragraphs {
                        let inlineSegments = parseInlineSegments(paragraph)
                        if !inlineSegments.isEmpty {
                            normalized.append(.richText(id: makeID(), segments: inlineSegments))
                        }
                    }
                }
            default:
                normalized.append(rebuiltPart(part))
            }
        }

        return normalized
    }
}

extension View {
    func assistantSingleSurfaceGlass(isLive: Bool) -> some View {
        singleSurfaceGlass(
            cornerRadius: 20,
            stableFillOpacity: isLive ? 0.01 : 0.004,
            tintOpacity: isLive ? 0.03 : 0.024,
            borderWidth: 0.85,
            darkBorderOpacity: 0.16,
            lightBorderOpacity: 0.09
        )
    }
}
