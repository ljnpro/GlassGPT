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
            if !Self.requiresFullReparse(forAppendedSuffix: suffix) {
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

    /// Clears retained parsed state when iOS reports memory pressure.
    public func handleMemoryPressure() {
        reset()
    }

    /// Returns true when the appended suffix still contains markdown span
    /// delimiters that could require reparsing the cached prefix. Complete
    /// thematic break lines such as `***` or `___` are ignored because once the
    /// newline has arrived they can no longer change preceding formatting.
    package static func requiresFullReparse(forAppendedSuffix text: String) -> Bool {
        hasUnclosedSpans(filteredHeuristicInput(text))
    }

    /// Checks whether the suffix contains unclosed Markdown spans that would
    /// make incremental parsing incorrect (e.g., an odd number of `**` or `` ` ``).
    private static func hasUnclosedSpans(_ text: String) -> Bool {
        let backtickCount = text.count(where: { $0 == "`" })
        if backtickCount % 2 != 0 { return true }

        let boldCount = text.components(separatedBy: "**").count - 1
        if boldCount % 2 != 0 { return true }

        let italicUnderscoreCount = text.components(separatedBy: "__").count - 1
        if italicUnderscoreCount % 2 != 0 { return true }

        return false
    }

    private static func filteredHeuristicInput(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let hasTrailingNewline = text.last?.isNewline == true
        var filteredLines: [String] = []
        filteredLines.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            let isCompleteLine = hasTrailingNewline || index < lines.count - 1
            if isCompleteLine, isThematicBreakLine(line) {
                continue
            }
            filteredLines.append(String(line))
        }

        return filteredLines.joined(separator: "\n")
    }

    private static func isThematicBreakLine(_ line: some StringProtocol) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        guard let marker = trimmed.first, marker == "*" || marker == "_" || marker == "-" else {
            return false
        }
        return trimmed.allSatisfy { $0 == marker }
    }
}
