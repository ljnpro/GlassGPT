import SwiftUI
@preconcurrency import WebKit

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let text: String

    // MARK: - Content Part

    private enum PartKind {
        case markdown
        case latexInline
        case latexBlock
        case codeBlock(language: String?)
    }

    private struct ContentPart: Identifiable {
        let id = UUID()
        let content: String
        let kind: PartKind
    }

    // MARK: - Parse Content

    private var contentParts: [ContentPart] {
        parseContent(text)
    }

    /// Parses text into interleaved markdown, LaTeX, and code block parts.
    /// Supports:
    ///   - Code blocks: ```lang\n...\n```
    ///   - Block LaTeX: \[...\], $$...$$
    ///   - Inline LaTeX: \(...\), $...$  (single $ must not span multiple lines)
    private func parseContent(_ input: String) -> [ContentPart] {
        // We scan the string character by character for reliability,
        // rather than using a single complex regex.

        var parts: [ContentPart] = []
        var markdownBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var i = 0

        func flushMarkdown() {
            let trimmed = markdownBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(ContentPart(content: markdownBuffer, kind: .markdown))
            }
            markdownBuffer = ""
        }

        while i < count {
            // --- Code block: ```
            if i + 2 < count && chars[i] == "`" && chars[i+1] == "`" && chars[i+2] == "`" {
                flushMarkdown()
                let start = i + 3
                // Read optional language tag (until newline)
                var langEnd = start
                while langEnd < count && chars[langEnd] != "\n" {
                    langEnd += 1
                }
                let lang = String(chars[start..<langEnd]).trimmingCharacters(in: .whitespaces)
                let codeStart = min(langEnd + 1, count)

                // Find closing ```
                var codeEnd = codeStart
                var found = false
                while codeEnd + 2 < count {
                    if chars[codeEnd] == "`" && chars[codeEnd+1] == "`" && chars[codeEnd+2] == "`" {
                        found = true
                        break
                    }
                    codeEnd += 1
                }

                if found {
                    let code = String(chars[codeStart..<codeEnd])
                    parts.append(ContentPart(content: code, kind: .codeBlock(language: lang.isEmpty ? nil : lang)))
                    i = codeEnd + 3
                    // Skip optional newline after closing ```
                    if i < count && chars[i] == "\n" { i += 1 }
                } else {
                    // No closing ``` found, treat as markdown
                    markdownBuffer += "```"
                    i = start
                }
                continue
            }

            // --- Block LaTeX: \[...\]
            if i + 1 < count && chars[i] == "\\" && chars[i+1] == "[" {
                flushMarkdown()
                let start = i + 2
                // Find closing \]
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\" && chars[end+1] == "]" {
                        found = true
                        break
                    }
                    end += 1
                }
                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        parts.append(ContentPart(content: latex, kind: .latexBlock))
                    }
                    i = end + 2
                } else {
                    markdownBuffer.append("\\[")
                    i = start
                }
                continue
            }

            // --- Inline LaTeX: \(...\)
            if i + 1 < count && chars[i] == "\\" && chars[i+1] == "(" {
                flushMarkdown()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\" && chars[end+1] == ")" {
                        found = true
                        break
                    }
                    end += 1
                }
                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        parts.append(ContentPart(content: latex, kind: .latexInline))
                    }
                    i = end + 2
                } else {
                    markdownBuffer.append("\\(")
                    i = start
                }
                continue
            }

            // --- Block LaTeX: $$...$$
            if i + 1 < count && chars[i] == "$" && chars[i+1] == "$" {
                flushMarkdown()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "$" && chars[end+1] == "$" {
                        found = true
                        break
                    }
                    end += 1
                }
                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        parts.append(ContentPart(content: latex, kind: .latexBlock))
                    }
                    i = end + 2
                } else {
                    markdownBuffer.append("$$")
                    i = start
                }
                continue
            }

            // --- Inline LaTeX: $...$  (single line only, not preceded by \)
            if chars[i] == "$" && (i == 0 || chars[i-1] != "\\") {
                // Look ahead for closing $ on the same line
                let start = i + 1
                var end = start
                var found = false
                while end < count && chars[end] != "\n" {
                    if chars[end] == "$" && chars[end-1] != "\\" {
                        found = true
                        break
                    }
                    end += 1
                }
                if found && end > start {
                    flushMarkdown()
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
                    if !latex.isEmpty {
                        parts.append(ContentPart(content: latex, kind: .latexInline))
                    }
                    i = end + 1
                } else {
                    markdownBuffer.append(chars[i])
                    i += 1
                }
                continue
            }

            // --- Regular character
            markdownBuffer.append(chars[i])
            i += 1
        }

        flushMarkdown()

        if parts.isEmpty {
            return [ContentPart(content: text, kind: .markdown)]
        }

        return parts
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(contentParts) { part in
                switch part.kind {
                case .codeBlock(let language):
                    CodeBlockView(language: language, code: part.content)
                case .latexInline:
                    LaTeXView(latex: part.content, isBlock: false)
                case .latexBlock:
                    LaTeXView(latex: part.content, isBlock: true)
                case .markdown:
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

        // Allow inline media playback
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator

        // Track the latex string to avoid unnecessary reloads
        context.coordinator.lastLatex = ""

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if content actually changed
        let key = "\(latex)-\(isDark)-\(isBlock)"
        guard key != context.coordinator.lastLatex else { return }
        context.coordinator.lastLatex = key

        // Encode the LaTeX string as a JSON string to safely embed it in JS
        // This handles all escaping automatically (backslashes, quotes, etc.)
        let encoder = JSONEncoder()
        let jsonLatex: String
        if let jsonData = try? encoder.encode(latex),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            jsonLatex = jsonStr  // Already includes surrounding quotes
        } else {
            // Fallback: manual escaping
            jsonLatex = "\"\(latex.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }

        let textColor = isDark ? "#e5e5e5" : "#1c1c1e"
        let displayMode = isBlock ? "true" : "false"
        let fontSize = isBlock ? "17px" : "16px"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css"
              crossorigin="anonymous">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"
                crossorigin="anonymous"></script>
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
            -webkit-text-size-adjust: none;
        }
        .katex { font-size: 1em !important; }
        .katex-display { margin: 4px 0 !important; }
        #math { display: inline-block; max-width: 100%; overflow-x: auto; }
        </style>
        </head>
        <body>
        <div id="math"></div>
        <script>
        document.addEventListener('DOMContentLoaded', function() {
            var latexStr = \(jsonLatex);
            try {
                katex.render(latexStr, document.getElementById('math'), {
                    displayMode: \(displayMode),
                    throwOnError: false,
                    trust: true,
                    strict: false
                });
            } catch(e) {
                document.getElementById('math').textContent = latexStr;
            }
            // Report rendered size back to native
            setTimeout(function() {
                var h = document.body.scrollHeight;
                if (h > 0) {
                    window.webkit.messageHandlers.sizeCallback.postMessage(h);
                }
            }, 150);
        });
        </script>
        </body>
        </html>
        """

        // Use a real base URL to allow CDN resource loading
        webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var lastLatex: String = ""

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
