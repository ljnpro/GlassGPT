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

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: sanitisedText,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

        // Don't strip fenced code blocks — the inline parser handles
        // backtick sequences gracefully enough for streaming preview.

        return result
    }
}
