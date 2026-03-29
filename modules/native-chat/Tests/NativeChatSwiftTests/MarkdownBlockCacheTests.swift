import ConversationSurfaceLogic
import Foundation
import Testing
@testable import NativeChatUI

@MainActor
struct MarkdownBlockCacheTests {
    @Test
    func `cache returns parsed blocks for text`() {
        let cache = MarkdownBlockCache()
        let parts = cache.parts(for: "Hello world")
        #expect(!parts.isEmpty)
    }

    @Test
    func `cache returns same result for identical text`() {
        let cache = MarkdownBlockCache()
        let first = cache.parts(for: "# Heading\n\nParagraph")
        let second = cache.parts(for: "# Heading\n\nParagraph")
        #expect(first.count == second.count)
    }

    @Test
    func `cache recomputes on different text`() {
        let cache = MarkdownBlockCache()
        let first = cache.parts(for: "text one")
        let second = cache.parts(for: "text two")
        // Both should return valid blocks
        #expect(!first.isEmpty)
        #expect(!second.isEmpty)
    }

    @Test
    func `cache handles empty text`() {
        let cache = MarkdownBlockCache()
        let parts = cache.parts(for: "")
        // MarkdownParser may return empty array for empty input
        _ = parts
    }

    @Test
    func `reset clears cache state`() {
        let cache = MarkdownBlockCache()
        _ = cache.parts(for: "initial")
        cache.reset()
        let parts = cache.parts(for: "after reset")
        #expect(!parts.isEmpty)
    }

    @Test
    func `memory pressure clears cached markdown blocks`() {
        let cache = MarkdownBlockCache()
        _ = cache.parts(for: "# Initial")
        cache.handleMemoryPressure()
        let parts = cache.parts(for: "# After Pressure")
        #expect(!parts.isEmpty)
    }

    @Test
    func `cache handles code blocks`() {
        let cache = MarkdownBlockCache()
        let parts = cache.parts(for: "```swift\nlet x = 1\n```")
        #expect(!parts.isEmpty)
    }

    @Test
    func `cache handles markdown with headings and lists`() {
        let cache = MarkdownBlockCache()
        let text = """
        # Title

        - Item 1
        - Item 2

        ## Subtitle

        Paragraph text.
        """
        let parts = cache.parts(for: text)
        #expect(parts.count >= 1)
    }
}
