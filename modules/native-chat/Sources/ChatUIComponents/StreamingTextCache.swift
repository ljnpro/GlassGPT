import Foundation
import SwiftUI

/// Caches incrementally-parsed attributed strings for streaming text to avoid
/// full O(n) re-parsing on every character append. When the new text is an
/// append-only extension of the cached text and the suffix contains no unclosed
/// Markdown spans, only the suffix is parsed and appended — turning O(n^2) over
/// the full response into amortised O(n).
@MainActor
public final class StreamingTextCache {
    private var cachedText = ""
    private var cachedResult: AttributedString = .init()

    /// Creates a new empty streaming text cache.
    public init() {}

    /// Returns an attributed string for the given text, reusing the cached prefix
    /// when possible.
    public func attributedString(for text: String) -> AttributedString {
        if !cachedText.isEmpty,
           text.hasPrefix(cachedText),
           text.count > cachedText.count {
            let suffix = String(text[text.index(text.startIndex, offsetBy: cachedText.count)...])
            if !hasUnclosedSpans(suffix) {
                let parsed = RichTextAttributedStringBuilder.parseStreamingText(suffix)
                cachedResult.append(parsed)
                cachedText = text
                return cachedResult
            }
        }

        // Full reparse fallback
        cachedResult = RichTextAttributedStringBuilder.parseStreamingText(text)
        cachedText = text
        return cachedResult
    }

    /// Resets the cache, forcing a full reparse on the next call.
    public func reset() {
        cachedText = ""
        cachedResult = .init()
    }

    /// Checks whether the suffix contains unclosed Markdown spans that would
    /// make incremental parsing incorrect (e.g., an odd number of `**` or `` ` ``).
    private func hasUnclosedSpans(_ text: String) -> Bool {
        let backtickCount = text.count(where: { $0 == "`" })
        if backtickCount % 2 != 0 { return true }

        let boldCount = text.components(separatedBy: "**").count - 1
        if boldCount % 2 != 0 { return true }

        let italicUnderscoreCount = text.components(separatedBy: "__").count - 1
        if italicUnderscoreCount % 2 != 0 { return true }

        return false
    }
}
