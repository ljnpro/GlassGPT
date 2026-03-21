import SwiftUI

/// Parses inline Markdown (bold, italic, code) into `AttributedString` values for display in SwiftUI text views.
public enum RichTextAttributedStringBuilder {
    struct Style {
        let baseFont: Font
        let boldFont: Font
        let italicFont: Font
        let boldItalicFont: Font
        let codeFont: Font
        let codeBackgroundColor: Color?
        let supportsUnderscoreBold: Bool
    }

    private static let bodyStyle = Style(
        baseFont: .body,
        boldFont: .body.bold(),
        italicFont: .body.italic(),
        boldItalicFont: .body.bold().italic(),
        codeFont: .body.monospaced(),
        codeBackgroundColor: .secondary.opacity(0.12),
        supportsUnderscoreBold: true
    )

    private static let captionStyle = Style(
        baseFont: .caption,
        boldFont: .caption.bold(),
        italicFont: .caption.italic(),
        boldItalicFont: .caption.bold().italic(),
        codeFont: .caption.monospaced(),
        codeBackgroundColor: nil,
        supportsUnderscoreBold: false
    )

    /// Parses body-styled Markdown text, preserving auto-detected links from Apple's parser.
    public static func parseRichText(_ text: String) -> AttributedString {
        parse(text, style: bodyStyle, preserveLinksFromAppleParser: true)
    }

    /// Parses body-styled Markdown suitable for live-streaming text where links are not yet stable.
    public static func parseStreamingText(_ text: String) -> AttributedString {
        parse(text, style: bodyStyle, preserveLinksFromAppleParser: false)
    }

    /// Parses caption-styled Markdown used for "thinking" indicator text.
    public static func parseThinkingText(_ text: String) -> AttributedString {
        parse(text, style: captionStyle, preserveLinksFromAppleParser: false)
    }

    private static func parse(
        _ text: String,
        style: Style,
        preserveLinksFromAppleParser: Bool
    ) -> AttributedString {
        if let appleResult = parsedMarkdownText(text) {
            let plainText = String(appleResult.characters)
            if !plainText.contains("**") {
                return appleResult
            }

            if preserveLinksFromAppleParser,
               appleResult.runs.contains(where: { $0.link != nil }) {
                return appleResult
            }
        }

        return manualMarkdownParse(text, style: style)
    }

    private static func parsedMarkdownText(_ text: String) -> AttributedString? {
        do {
            return try AttributedString(
                markdown: text,
                options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return nil
        }
    }

    private static func manualMarkdownParse(_ text: String, style: Style) -> AttributedString {
        var result = AttributedString()
        let chars = Array(text)
        let count = chars.count
        var index = 0
        var currentText = ""

        func flushCurrent() {
            guard !currentText.isEmpty else { return }

            var chunk = AttributedString(currentText)
            chunk.font = style.baseFont
            result += chunk
            currentText = ""
        }

        while index < count {
            if let parsed = consumeCodeSpan(chars, index: index, style: style) {
                flushCurrent()
                result += parsed.chunk
                index = parsed.nextIndex
                continue
            }

            if let parsed = consumeBoldItalicSpan(chars, index: index, style: style) {
                flushCurrent()
                result += parsed.chunk
                index = parsed.nextIndex
                continue
            }

            if let parsed = consumeBoldSpan(chars, index: index, style: style) {
                flushCurrent()
                result += parsed.chunk
                index = parsed.nextIndex
                continue
            }

            if let parsed = consumeUnderscoreBoldSpan(chars, index: index, style: style) {
                flushCurrent()
                result += parsed.chunk
                index = parsed.nextIndex
                continue
            }

            if let parsed = consumeItalicSpan(chars, index: index, style: style) {
                flushCurrent()
                result += parsed.chunk
                index = parsed.nextIndex
                continue
            }

            currentText.append(chars[index])
            index += 1
        }

        flushCurrent()
        return result
    }

    private static func consumeCodeSpan(
        _ chars: [Character],
        index: Int,
        style: Style
    ) -> (chunk: AttributedString, nextIndex: Int)? {
        guard chars[index] == "`" else { return nil }

        var end = index + 1
        while end < chars.count, chars[end] != "`" {
            end += 1
        }
        guard end < chars.count else { return nil }

        var chunk = AttributedString(String(chars[(index + 1) ..< end]))
        chunk.font = style.codeFont
        if let codeBackgroundColor = style.codeBackgroundColor {
            chunk.backgroundColor = codeBackgroundColor
        }
        return (chunk, end + 1)
    }

    private static func consumeBoldItalicSpan(
        _ chars: [Character],
        index: Int,
        style: Style
    ) -> (chunk: AttributedString, nextIndex: Int)? {
        guard index + 2 < chars.count,
              chars[index] == "*",
              chars[index + 1] == "*",
              chars[index + 2] == "*" else {
            return nil
        }

        var end = index + 3
        while end + 2 < chars.count {
            if chars[end] == "*", chars[end + 1] == "*", chars[end + 2] == "*" {
                break
            }
            end += 1
        }
        guard end + 2 < chars.count else { return nil }

        let content = String(chars[(index + 3) ..< end])
        return (styledChunk(content, font: style.boldItalicFont), end + 3)
    }

    private static func consumeBoldSpan(
        _ chars: [Character],
        index: Int,
        style: Style
    ) -> (chunk: AttributedString, nextIndex: Int)? {
        guard index + 1 < chars.count,
              chars[index] == "*",
              chars[index + 1] == "*" else {
            return nil
        }

        var end = index + 2
        while end + 1 < chars.count {
            if chars[end] == "*", chars[end + 1] == "*" {
                break
            }
            end += 1
        }
        guard end + 1 < chars.count else { return nil }

        let content = String(chars[(index + 2) ..< end])
        return (styledChunk(content, font: style.boldFont), end + 2)
    }

    private static func consumeUnderscoreBoldSpan(
        _ chars: [Character],
        index: Int,
        style: Style
    ) -> (chunk: AttributedString, nextIndex: Int)? {
        guard style.supportsUnderscoreBold,
              index + 1 < chars.count,
              chars[index] == "_",
              chars[index + 1] == "_" else {
            return nil
        }

        var end = index + 2
        while end + 1 < chars.count {
            if chars[end] == "_", chars[end + 1] == "_" {
                break
            }
            end += 1
        }
        guard end + 1 < chars.count else { return nil }

        let content = String(chars[(index + 2) ..< end])
        return (styledChunk(content, font: style.boldFont), end + 2)
    }

    private static func consumeItalicSpan(
        _ chars: [Character],
        index: Int,
        style: Style
    ) -> (chunk: AttributedString, nextIndex: Int)? {
        guard chars[index] == "*" || chars[index] == "_" else {
            return nil
        }

        let marker = chars[index]
        guard index + 1 < chars.count, chars[index + 1] != marker else {
            return nil
        }

        var end = index + 1
        while end < chars.count {
            if chars[end] == marker, end + 1 >= chars.count || chars[end + 1] != marker {
                break
            }
            end += 1
        }
        guard end < chars.count else { return nil }

        let content = String(chars[(index + 1) ..< end])
        return (styledChunk(content, font: style.italicFont), end + 1)
    }

    private static func styledChunk(_ content: String, font: Font) -> AttributedString {
        var chunk = AttributedString(content)
        chunk.font = font
        return chunk
    }
}
