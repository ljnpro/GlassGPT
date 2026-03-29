import ConversationSurfaceLogic
import Foundation

/// Caches `[BlockPart]` by text content to avoid re-parsing unchanged Markdown.
/// The cache stores the last parsed result and only recomputes when the text changes.
@MainActor
package final class MarkdownBlockCache {
    private var cachedText = ""
    private var cachedParts: [BlockPart] = []

    /// Creates a new empty block cache.
    package init() {}

    /// Returns block parts for the given text, reusing cached results when text is unchanged.
    package func parts(for text: String) -> [BlockPart] {
        if text == cachedText {
            return cachedParts
        }
        cachedParts = MarkdownParser.parseBlocks(text)
        cachedText = text
        return cachedParts
    }

    /// Clears the cached blocks, forcing reparse on next access.
    package func reset() {
        cachedText = ""
        cachedParts = []
    }
}
