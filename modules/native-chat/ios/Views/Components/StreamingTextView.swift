import SwiftUI

/// A lightweight text view optimised for streaming.
///
/// During streaming, re-parsing the full Markdown/LaTeX/code-block hierarchy
/// on every single delta is expensive (especially WKWebView creation for LaTeX).
/// This view renders the incoming text as basic attributed Markdown (bold,
/// italic, inline code, links) without creating any WKWebViews or heavy
/// sub-views. Once streaming finishes, the caller should swap this out for
/// the full `MarkdownContentView`.
struct StreamingTextView: View {
    let text: String
    var allowsSelection: Bool = false

    var body: some View {
        let attributed = robustMarkdownParse(sanitisedText)
        Text(attributed)
            .font(.body)
            .applyingIf(allowsSelection) { view in
                view.textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Strip LaTeX delimiters and fenced code-block markers so the
    /// inline Markdown parser doesn't choke on them.
    private var sanitisedText: String {
        var result = text

        // Replace block LaTeX delimiters with placeholder
        result = result.replacingOccurrences(
            of: #"\\\[[\s\S]*?\\\]"#,
            with: " [math] ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\$\$[\s\S]*?\$\$"#,
            with: " [math] ",
            options: .regularExpression
        )

        // Replace inline LaTeX
        result = result.replacingOccurrences(
            of: #"\\\([\s\S]*?\\\)"#,
            with: "[math]",
            options: .regularExpression
        )

        return result
    }

    /// Robust Markdown parser: try Apple's parser first, fall back to manual
    /// parsing if the result still contains literal `**` markers (common with
    /// CJK text where punctuation after ** breaks CommonMark emphasis rules).
    private func robustMarkdownParse(_ text: String) -> AttributedString {
        if let appleResult = try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            let plainText = String(appleResult.characters)
            if !plainText.contains("**") {
                return appleResult
            }
        }

        return manualMarkdownParse(text)
    }

    /// Manual inline Markdown parser for bold, italic, bold+italic, and inline code.
    private func manualMarkdownParse(_ text: String) -> AttributedString {
        var result = AttributedString()
        let chars = Array(text)
        let count = chars.count
        var i = 0
        var currentText = ""

        func flushPlain() {
            if !currentText.isEmpty {
                var chunk = AttributedString(currentText)
                chunk.font = .body
                result += chunk
                currentText = ""
            }
        }

        while i < count {
            // Inline code: `...`
            if chars[i] == "`" {
                var end = i + 1
                while end < count && chars[end] != "`" { end += 1 }
                if end < count {
                    flushPlain()
                    let codeContent = String(chars[(i + 1)..<end])
                    var chunk = AttributedString(codeContent)
                    chunk.font = .body.monospaced()
                    chunk.backgroundColor = .secondary.opacity(0.12)
                    result += chunk
                    i = end + 1
                    continue
                }
            }

            // Bold+Italic: ***...***
            if i + 2 < count && chars[i] == "*" && chars[i + 1] == "*" && chars[i + 2] == "*" {
                var end = i + 3
                while end + 2 < count {
                    if chars[end] == "*" && chars[end + 1] == "*" && chars[end + 2] == "*" { break }
                    end += 1
                }
                if end + 2 < count {
                    flushPlain()
                    let content = String(chars[(i + 3)..<end])
                    var chunk = AttributedString(content)
                    chunk.font = .body.bold().italic()
                    result += chunk
                    i = end + 3
                    continue
                }
            }

            // Bold: **...** or __...__
            if i + 1 < count && ((chars[i] == "*" && chars[i + 1] == "*") || (chars[i] == "_" && chars[i + 1] == "_")) {
                let marker = chars[i]
                var end = i + 2
                while end + 1 < count {
                    if chars[end] == marker && chars[end + 1] == marker { break }
                    end += 1
                }
                if end + 1 < count {
                    flushPlain()
                    let content = String(chars[(i + 2)..<end])
                    var chunk = AttributedString(content)
                    chunk.font = .body.bold()
                    result += chunk
                    i = end + 2
                    continue
                }
            }

            // Italic: *...* or _..._
            if chars[i] == "*" || chars[i] == "_" {
                let marker = chars[i]
                if i + 1 < count && chars[i + 1] != marker {
                    var end = i + 1
                    while end < count {
                        if chars[end] == marker && (end + 1 >= count || chars[end + 1] != marker) { break }
                        end += 1
                    }
                    if end < count {
                        flushPlain()
                        let content = String(chars[(i + 1)..<end])
                        var chunk = AttributedString(content)
                        chunk.font = .body.italic()
                        result += chunk
                        i = end + 1
                        continue
                    }
                }
            }

            currentText.append(chars[i])
            i += 1
        }

        flushPlain()
        return result
    }
}
