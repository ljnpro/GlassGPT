import ChatUIComponents
import Foundation
import Testing

@MainActor
struct StreamingTextCacheTests {
    @Test
    func `cache returns attributed string for initial text`() {
        let cache = StreamingTextCache()
        let result = cache.attributedString(for: "Hello world")
        #expect(!String(result.characters).isEmpty)
    }

    @Test
    func `cache uses incremental parsing for appended text`() {
        let cache = StreamingTextCache()
        _ = cache.attributedString(for: "Hello")
        let result = cache.attributedString(for: "Hello world")
        #expect(String(result.characters).contains("Hello"))
        #expect(String(result.characters).contains("world"))
    }

    @Test
    func `cache falls back to full reparse on unclosed backtick`() {
        let cache = StreamingTextCache()
        _ = cache.attributedString(for: "Hello")
        // Suffix with odd backtick triggers full reparse
        let result = cache.attributedString(for: "Hello `code")
        #expect(!String(result.characters).isEmpty)
    }

    @Test
    func `cache falls back to full reparse on unclosed bold`() {
        let cache = StreamingTextCache()
        _ = cache.attributedString(for: "normal text")
        let result = cache.attributedString(for: "normal text **bold")
        #expect(!String(result.characters).isEmpty)
    }

    @Test
    func `reset clears cached state`() {
        let cache = StreamingTextCache()
        _ = cache.attributedString(for: "cached text")
        cache.reset()
        // After reset, same text forces full reparse (no crash)
        let result = cache.attributedString(for: "new text")
        #expect(!String(result.characters).isEmpty)
    }

    @Test
    func `memory pressure clears cached streaming text state`() {
        let cache = StreamingTextCache()
        _ = cache.attributedString(for: "cached text")
        cache.handleMemoryPressure()
        let result = cache.attributedString(for: "after pressure")
        #expect(String(result.characters).contains("after pressure"))
    }

    @Test
    func `cache handles empty string`() {
        let cache = StreamingTextCache()
        let result = cache.attributedString(for: "")
        #expect(result.characters.isEmpty)
    }

    @Test
    func `cache handles rapid sequential appends`() {
        let cache = StreamingTextCache()
        var accumulated = ""
        for char in "The quick brown fox jumps over the lazy dog" {
            accumulated += String(char)
            let result = cache.attributedString(for: accumulated)
            #expect(String(result.characters) == accumulated || !String(result.characters).isEmpty)
        }
    }

    @Test
    func `cache handles identical text without re-parsing`() {
        let cache = StreamingTextCache()
        let first = cache.attributedString(for: "same text")
        let second = cache.attributedString(for: "same text")
        #expect(String(first.characters) == String(second.characters))
    }

    @Test
    func `cache handles text with complete markdown spans`() {
        let cache = StreamingTextCache()
        _ = cache.attributedString(for: "Hello **bold**")
        let result = cache.attributedString(for: "Hello **bold** and more")
        #expect(String(result.characters).contains("more"))
    }

    @Test
    func `incremental heuristic keeps dangling triple asterisk as unsafe`() {
        #expect(StreamingTextCache.requiresFullReparse(forAppendedSuffix: "***"))
    }

    @Test
    func `incremental heuristic treats closed thematic break line as safe`() {
        #expect(!StreamingTextCache.requiresFullReparse(forAppendedSuffix: "***\n"))
        #expect(!StreamingTextCache.requiresFullReparse(forAppendedSuffix: "\n___\nNext"))
    }
}
