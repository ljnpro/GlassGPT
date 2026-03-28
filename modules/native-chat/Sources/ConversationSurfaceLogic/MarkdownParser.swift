import Foundation

/// Entry point for converting Markdown source text into structured block parts.
package enum MarkdownParser {
    package static func parseBlocks(_ input: String) -> [BlockPart] {
        let firstPass = parsePrimaryBlocks(input)
        guard !firstPass.isEmpty else {
            return [.richText(id: 0, segments: [.text(input)])]
        }

        let finalParts = expandRichTextParts(firstPass)
        let result = reindexBlockParts(finalParts)
        return result.isEmpty ? [.richText(id: 0, segments: [.text(input)])] : result
    }
}
