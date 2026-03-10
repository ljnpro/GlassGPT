import SwiftUI
@preconcurrency import WebKit

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let text: String

    // MARK: - Content Part

    private struct ContentPart: Identifiable {
        let id = UUID()
        let content: String
        let isLatex: Bool
        let isBlock: Bool
        let isCodeBlock: Bool
        let codeLanguage: String?
    }

    // MARK: - Parse Content

    private var contentParts: [ContentPart] {
        var parts: [ContentPart] = []

        // Combined pattern: code blocks, block LaTeX ($$...$$), inline LaTeX ($...$)
        let pattern = #"```(\w*)\n([\s\S]*?)```|(?<!\\)(\$\$)([\s\S]*?)(?<!\\)\$\$|(?<!\\)(\$)(.+?)(?<!\\)\$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [ContentPart(content: text, isLatex: false, isBlock: false, isCodeBlock: false, codeLanguage: nil)]
        }

        var currentPosition = text.startIndex

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            // Add markdown text before this match
            if matchRange.lowerBound > currentPosition {
                let markdownContent = String(text[currentPosition..<matchRange.lowerBound])
                if !markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(ContentPart(content: markdownContent, isLatex: false, isBlock: false, isCodeBlock: false, codeLanguage: nil))
                }
            }

            // Check which group matched
            if let langRange = Range(match.range(at: 1), in: text),
               let codeRange = Range(match.range(at: 2), in: text) {
                // Code block (```lang\ncode```)
                let lang = String(text[langRange])
                let code = String(text[codeRange])
                parts.append(ContentPart(content: code, isLatex: false, isBlock: true, isCodeBlock: true, codeLanguage: lang.isEmpty ? nil : lang))
            } else if Range(match.range(at: 3), in: text) != nil,
                      let blockContentRange = Range(match.range(at: 4), in: text) {
                // Block LaTeX ($$...$$)
                let latexContent = String(text[blockContentRange])
                parts.append(ContentPart(content: latexContent, isLatex: true, isBlock: true, isCodeBlock: false, codeLanguage: nil))
            } else if let inlineContentRange = Range(match.range(at: 6), in: text) {
                // Inline LaTeX ($...$)
                let latexContent = String(text[inlineContentRange])
                parts.append(ContentPart(content: latexContent, isLatex: true, isBlock: false, isCodeBlock: false, codeLanguage: nil))
            }

            currentPosition = matchRange.upperBound
        }

        // Add remaining markdown
        if currentPosition < text.endIndex {
            let rest = String(text[currentPosition...])
            if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(ContentPart(content: rest, isLatex: false, isBlock: false, isCodeBlock: false, codeLanguage: nil))
            }
        }

        if parts.isEmpty {
            return [ContentPart(content: text, isLatex: false, isBlock: false, isCodeBlock: false, codeLanguage: nil)]
        }

        return parts
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(contentParts) { part in
                if part.isCodeBlock {
                    CodeBlockView(language: part.codeLanguage, code: part.content)
                } else if part.isLatex {
                    LaTeXView(latex: part.content, isBlock: part.isBlock)
                } else {
                    NativeMarkdownView(text: part.content)
                }
            }
        }
    }
}

// MARK: - Native Markdown View (iOS 15+ AttributedString)

private struct NativeMarkdownView: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .font(.body)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

// MARK: - LaTeX View (WKWebView-based with KaTeX)

struct LaTeXView: View {
    let latex: String
    let isBlock: Bool

    @State private var height: CGFloat = 24
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LaTeXWebView(
            latex: latex,
            isBlock: isBlock,
            isDark: colorScheme == .dark,
            height: $height
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: isBlock ? .center : .leading)
    }
}

// MARK: - LaTeX WKWebView Wrapper

@MainActor
private struct LaTeXWebView: UIViewRepresentable {
    let latex: String
    let isBlock: Bool
    let isDark: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "sizeCallback")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let escapedLatex = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let textColor = isDark ? "#e5e5e5" : "#1c1c1e"
        let displayMode = isBlock ? "true" : "false"
        let fontSize = isBlock ? "17px" : "16px"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: transparent;
            color: \(textColor);
            font-size: \(fontSize);
            display: flex;
            align-items: center;
            justify-content: \(isBlock ? "center" : "flex-start");
            min-height: 20px;
            padding: 2px 0;
        }
        .katex { font-size: 1em; }
        .katex-display { margin: 4px 0; }
        #math { display: inline-block; }
        </style>
        </head>
        <body>
        <div id="math"></div>
        <script>
        try {
            katex.render(`\(escapedLatex)`, document.getElementById('math'), {
                displayMode: \(displayMode),
                throwOnError: false,
                trust: true,
                strict: false
            });
        } catch(e) {
            document.getElementById('math').textContent = `\(escapedLatex)`;
        }
        // Report size back to native
        setTimeout(function() {
            var h = document.body.scrollHeight;
            window.webkit.messageHandlers.sizeCallback.postMessage(h);
        }, 100);
        </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat

        init(height: Binding<CGFloat>) {
            _height = height
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let newHeight: CGFloat
            if let h = message.body as? CGFloat {
                newHeight = max(h, 20)
            } else if let h = message.body as? Int {
                newHeight = max(CGFloat(h), 20)
            } else if let h = message.body as? Double {
                newHeight = max(CGFloat(h), 20)
            } else {
                return
            }
            Task { @MainActor in
                self.height = newHeight
            }
        }
    }
}
