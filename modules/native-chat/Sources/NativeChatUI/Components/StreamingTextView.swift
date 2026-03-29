import ChatUIComponents
import SwiftUI

/// A lightweight text view optimised for streaming.
///
/// During streaming, re-parsing the full Markdown/LaTeX/code-block hierarchy
/// on every single delta is expensive (especially WKWebView creation for LaTeX).
/// This view renders the incoming text as basic attributed Markdown (bold,
/// italic, inline code, links) without creating any WKWebViews or heavy
/// sub-views. Once streaming finishes, the caller should swap this out for
/// the full `MarkdownContentView`.
public struct StreamingTextView: View {
    let text: String
    var allowsSelection = false
    @State private var cache = StreamingTextCache()

    /// Creates a streaming text view for the given incremental response text.
    public init(text: String, allowsSelection: Bool = false) {
        self.text = text
        self.allowsSelection = allowsSelection
    }

    /// The lightweight streaming-text rendering used while a reply is still in flight.
    public var body: some View {
        let attributed = cache.attributedString(for: sanitisedText)
        Text(attributed)
            .font(.body)
            .applyingIf(allowsSelection) { view in
                view.textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(sanitisedText)
            .accessibilityIdentifier("chat.streamingText")
    }

    /// Strip LaTeX delimiters and fenced code-block markers so the
    /// inline Markdown parser doesn't choke on them.
    private var sanitisedText: String {
        Self.sanitiseText(text)
    }

    /// Strips LaTeX delimiters and fenced code-block markers from the text for safe inline Markdown parsing.
    public static func sanitiseText(_ text: String) -> String {
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
}
