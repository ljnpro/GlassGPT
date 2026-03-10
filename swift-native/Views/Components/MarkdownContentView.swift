import SwiftUI
import MarkdownUI
import LaTeXSwiftUI

struct MarkdownContentView: View {
    let text: String

    // MARK: - Content Part

    private struct ContentPart: Identifiable {
        let id = UUID()
        let content: String
        let isLatex: Bool
        let isBlock: Bool
    }

    // MARK: - Parse LaTeX

    private var contentParts: [ContentPart] {
        var parts: [ContentPart] = []
        var currentPosition = text.startIndex

        // Match both block ($$...$$) and inline ($...$) LaTeX
        let pattern = #"(?<!\\)(\$\$)([\s\S]*?)(?<!\\)\$\$|(?<!\\)(\$)(.+?)(?<!\\)\$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [ContentPart(content: text, isLatex: false, isBlock: false)]
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            // Add Markdown before this match
            if matchRange.lowerBound > currentPosition {
                let markdownContent = String(text[currentPosition..<matchRange.lowerBound])
                if !markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(ContentPart(content: markdownContent, isLatex: false, isBlock: false))
                }
            }

            // Determine if block or inline
            if Range(match.range(at: 1), in: text) != nil,
               let blockContentRange = Range(match.range(at: 2), in: text) {
                // Block LaTeX ($$...$$)
                let latexContent = String(text[blockContentRange])
                parts.append(ContentPart(content: latexContent, isLatex: true, isBlock: true))
            } else if let inlineContentRange = Range(match.range(at: 4), in: text) {
                // Inline LaTeX ($...$)
                let latexContent = String(text[inlineContentRange])
                parts.append(ContentPart(content: latexContent, isLatex: true, isBlock: false))
            }

            currentPosition = matchRange.upperBound
        }

        // Add remaining Markdown
        if currentPosition < text.endIndex {
            let remaining = String(text[currentPosition...])
            if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(ContentPart(content: remaining, isLatex: false, isBlock: false))
            }
        }

        if parts.isEmpty {
            return [ContentPart(content: text, isLatex: false, isBlock: false)]
        }

        return parts
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(contentParts) { part in
                if part.isLatex {
                    LaTeX(part.content)
                        .blockMode(part.isBlock ? .blockText : .alwaysInline)
                        .font(.body)
                        .foregroundStyle(.primary)
                } else {
                    Markdown(part.content)
                        .markdownTheme(.gitHub)
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            CodeBlockView(
                                language: configuration.language,
                                code: configuration.content
                            )
                        }
                }
            }
        }
    }
}
