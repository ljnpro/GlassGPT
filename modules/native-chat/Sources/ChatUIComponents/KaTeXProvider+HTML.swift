import ConversationSurfaceLogic
import Foundation

public extension KaTeXProvider {
    /// Generates a self-contained HTML page that renders the given LaTeX string using KaTeX.
    ///
    /// Falls back to CDN-hosted KaTeX when offline bundle resources are unavailable.
    static func htmlForLatex(
        _ latex: String,
        isDark: Bool,
        measurementToken: String,
        maxWidth: CGFloat
    ) -> (html: String, baseURL: URL?) {
        KaTeXHTMLDocumentBuilder.makeDocument(
            latex: latex,
            isDark: isDark,
            measurementToken: measurementToken,
            maxWidth: maxWidth,
            assets: .init(
                css: cssContent,
                js: jsContent,
                baseURL: baseURL
            )
        )
    }
}
