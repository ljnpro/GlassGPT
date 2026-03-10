import SwiftUI
@preconcurrency import WebKit

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let text: String

    // MARK: - Block-level Part

    /// Block-level parts are rendered in a VStack.
    /// "richText" parts contain interleaved markdown and inline LaTeX rendered as a single Text view.
    private enum BlockPart: Identifiable {
        case richText(id: UUID = UUID(), segments: [InlineSegment])
        case latexBlock(id: UUID = UUID(), content: String)
        case codeBlock(id: UUID = UUID(), language: String?, code: String)

        var id: UUID {
            switch self {
            case .richText(let id, _): return id
            case .latexBlock(let id, _): return id
            case .codeBlock(let id, _, _): return id
            }
        }
    }

    /// Inline segments within a richText block
    private enum InlineSegment {
        case text(String)
        case latexInline(String)
    }

    // MARK: - Parse Content

    private var blockParts: [BlockPart] {
        parseBlocks(text)
    }

    /// First pass: extract code blocks and block-level LaTeX.
    /// Everything else is grouped into "inline" chunks that may contain inline LaTeX.
    private func parseBlocks(_ input: String) -> [BlockPart] {
        var parts: [BlockPart] = []
        var inlineBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var i = 0

        func flushInline() {
            if !inlineBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let segments = parseInlineSegments(inlineBuffer)
                parts.append(.richText(segments: segments))
            }
            inlineBuffer = ""
        }

        while i < count {
            // --- Code block: ```
            if i + 2 < count && chars[i] == "`" && chars[i+1] == "`" && chars[i+2] == "`" {
                flushInline()
                let start = i + 3
                var langEnd = start
                while langEnd < count && chars[langEnd] != "\n" { langEnd += 1 }
                let lang = String(chars[start..<langEnd]).trimmingCharacters(in: .whitespaces)
                let codeStart = min(langEnd + 1, count)

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
                    parts.append(.codeBlock(language: lang.isEmpty ? nil : lang, code: code))
                    i = codeEnd + 3
                    if i < count && chars[i] == "\n" { i += 1 }
                } else {
                    inlineBuffer += "```"
                    i = start
                }
                continue
            }

            // --- Block LaTeX: \[...\]
            if i + 1 < count && chars[i] == "\\" && chars[i+1] == "[" {
                flushInline()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\" && chars[end+1] == "]" { found = true; break }
                    end += 1
                }
                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty { parts.append(.latexBlock(content: latex)) }
                    i = end + 2
                } else {
                    inlineBuffer.append("\\[")
                    i = start
                }
                continue
            }

            // --- Block LaTeX: $$...$$
            if i + 1 < count && chars[i] == "$" && chars[i+1] == "$" {
                flushInline()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "$" && chars[end+1] == "$" { found = true; break }
                    end += 1
                }
                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty { parts.append(.latexBlock(content: latex)) }
                    i = end + 2
                } else {
                    inlineBuffer.append("$$")
                    i = start
                }
                continue
            }

            // Everything else goes into inline buffer
            inlineBuffer.append(chars[i])
            i += 1
        }

        flushInline()

        if parts.isEmpty {
            return [.richText(segments: [.text(text)])]
        }

        return parts
    }

    /// Second pass: within an inline chunk, split out \(...\) and $...$ as inline LaTeX segments.
    private func parseInlineSegments(_ input: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var textBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var i = 0

        func flushText() {
            if !textBuffer.isEmpty {
                segments.append(.text(textBuffer))
                textBuffer = ""
            }
        }

        while i < count {
            // --- Inline LaTeX: \(...\)
            if i + 1 < count && chars[i] == "\\" && chars[i+1] == "(" {
                flushText()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\" && chars[end+1] == ")" { found = true; break }
                    end += 1
                }
                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
                    if !latex.isEmpty {
                        segments.append(.latexInline(latex))
                    }
                    i = end + 2
                } else {
                    textBuffer.append("\\(")
                    i = start
                }
                continue
            }

            // --- Inline LaTeX: $...$ (single line, not preceded by \)
            if chars[i] == "$" && (i == 0 || chars[i-1] != "\\") {
                let start = i + 1
                var end = start
                var found = false
                while end < count && chars[end] != "\n" {
                    if chars[end] == "$" && (end == start || chars[end-1] != "\\") {
                        found = true
                        break
                    }
                    end += 1
                }
                if found && end > start {
                    flushText()
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
                    if !latex.isEmpty {
                        segments.append(.latexInline(latex))
                    }
                    i = end + 1
                } else {
                    textBuffer.append(chars[i])
                    i += 1
                }
                continue
            }

            textBuffer.append(chars[i])
            i += 1
        }

        flushText()
        return segments
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(blockParts) { part in
                switch part {
                case .codeBlock(_, let language, let code):
                    CodeBlockView(language: language, code: code)

                case .latexBlock(_, let content):
                    BlockLaTeXView(latex: content)
                        .padding(.vertical, 2)

                case .richText(_, let segments):
                    RichTextView(segments: segments)
                }
            }
        }
    }
}

// MARK: - Rich Text View (Markdown + Inline LaTeX as a single Text)

private struct RichTextView: View {
    let segments: [MarkdownContentView.InlineSegment]

    var body: some View {
        // Build a single Text by concatenating markdown and inline LaTeX
        // Inline LaTeX is converted to italic Unicode representation
        let combinedText = segments.map { segment in
            switch segment {
            case .text(let str):
                return str
            case .latexInline(let latex):
                // Convert simple LaTeX to Unicode for inline display
                return latexToUnicode(latex)
            }
        }.joined()

        if let attributed = try? AttributedString(
            markdown: combinedText,
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
            Text(combinedText)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    /// Convert common LaTeX expressions to Unicode text for inline display.
    /// This handles Greek letters, superscripts, subscripts, and common math symbols.
    private func latexToUnicode(_ latex: String) -> String {
        var result = latex

        // Greek letters
        let greekMap: [(String, String)] = [
            ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
            ("\\epsilon", "ε"), ("\\varepsilon", "ε"), ("\\zeta", "ζ"), ("\\eta", "η"),
            ("\\theta", "θ"), ("\\vartheta", "ϑ"), ("\\iota", "ι"), ("\\kappa", "κ"),
            ("\\lambda", "λ"), ("\\mu", "μ"), ("\\nu", "ν"), ("\\xi", "ξ"),
            ("\\pi", "π"), ("\\varpi", "ϖ"), ("\\rho", "ρ"), ("\\varrho", "ϱ"),
            ("\\sigma", "σ"), ("\\varsigma", "ς"), ("\\tau", "τ"), ("\\upsilon", "υ"),
            ("\\phi", "φ"), ("\\varphi", "φ"), ("\\chi", "χ"), ("\\psi", "ψ"),
            ("\\omega", "ω"),
            ("\\Gamma", "Γ"), ("\\Delta", "Δ"), ("\\Theta", "Θ"), ("\\Lambda", "Λ"),
            ("\\Xi", "Ξ"), ("\\Pi", "Π"), ("\\Sigma", "Σ"), ("\\Upsilon", "Υ"),
            ("\\Phi", "Φ"), ("\\Psi", "Ψ"), ("\\Omega", "Ω"),
        ]

        for (cmd, unicode) in greekMap {
            result = result.replacingOccurrences(of: cmd, with: unicode)
        }

        // Common math symbols
        let symbolMap: [(String, String)] = [
            ("\\infty", "∞"), ("\\partial", "∂"), ("\\nabla", "∇"),
            ("\\times", "×"), ("\\cdot", "·"), ("\\div", "÷"),
            ("\\pm", "±"), ("\\mp", "∓"), ("\\leq", "≤"), ("\\geq", "≥"),
            ("\\neq", "≠"), ("\\approx", "≈"), ("\\equiv", "≡"),
            ("\\in", "∈"), ("\\notin", "∉"), ("\\subset", "⊂"), ("\\supset", "⊃"),
            ("\\cup", "∪"), ("\\cap", "∩"), ("\\emptyset", "∅"),
            ("\\forall", "∀"), ("\\exists", "∃"),
            ("\\rightarrow", "→"), ("\\leftarrow", "←"), ("\\Rightarrow", "⇒"),
            ("\\Leftarrow", "⇐"), ("\\leftrightarrow", "↔"),
            ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"),
            ("\\sqrt", "√"), ("\\angle", "∠"), ("\\degree", "°"),
            ("\\circ", "∘"), ("\\bullet", "•"),
            ("\\ldots", "…"), ("\\cdots", "⋯"), ("\\vdots", "⋮"),
            ("\\vec{", ""), // handled separately
            ("\\overrightarrow{", ""), // handled separately
        ]

        for (cmd, unicode) in symbolMap {
            if !cmd.hasSuffix("{") {
                result = result.replacingOccurrences(of: cmd, with: unicode)
            }
        }

        // Handle \vec{X} → X⃗
        let vecPattern = try? NSRegularExpression(pattern: #"\\vec\{([^}]+)\}"#)
        if let vecPattern = vecPattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = vecPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1\u{20D7}")
        }

        // Handle \overrightarrow{X} → X⃗
        let arrowPattern = try? NSRegularExpression(pattern: #"\\overrightarrow\{([^}]+)\}"#)
        if let arrowPattern = arrowPattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = arrowPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1\u{20D7}")
        }

        // Handle \frac{a}{b} → a/b
        let fracPattern = try? NSRegularExpression(pattern: #"\\frac\{([^}]+)\}\{([^}]+)\}"#)
        if let fracPattern = fracPattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = fracPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1/$2")
        }

        // Handle simple subscripts: _{x} → subscript
        let subMap: [Character: String] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
            "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
            "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
            "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
            "v": "ᵥ", "x": "ₓ",
        ]

        let supMap: [Character: String] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
            "n": "ⁿ", "i": "ⁱ",
            "+": "⁺", "-": "⁻", "(": "⁽", ")": "⁾",
        ]

        // Handle ^{...} superscripts
        let supPattern = try? NSRegularExpression(pattern: #"\^\{([^}]+)\}"#)
        if let supPattern = supPattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = supPattern.matches(in: result, range: nsRange).reversed()
            var mutableResult = result
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: mutableResult),
                   let fullRange = Range(match.range, in: mutableResult) {
                    let content = String(mutableResult[contentRange])
                    let converted = content.map { supMap[$0] ?? String($0) }.joined()
                    mutableResult.replaceSubrange(fullRange, with: converted)
                }
            }
            result = mutableResult
        }

        // Handle ^x single char superscript
        let supSinglePattern = try? NSRegularExpression(pattern: #"\^([0-9a-zA-Z])"#)
        if let supSinglePattern = supSinglePattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = supSinglePattern.matches(in: result, range: nsRange).reversed()
            var mutableResult = result
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: mutableResult),
                   let fullRange = Range(match.range, in: mutableResult) {
                    let ch = mutableResult[contentRange].first!
                    let converted = supMap[ch] ?? String(ch)
                    mutableResult.replaceSubrange(fullRange, with: converted)
                }
            }
            result = mutableResult
        }

        // Handle _{...} subscripts
        let subPattern = try? NSRegularExpression(pattern: #"_\{([^}]+)\}"#)
        if let subPattern = subPattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = subPattern.matches(in: result, range: nsRange).reversed()
            var mutableResult = result
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: mutableResult),
                   let fullRange = Range(match.range, in: mutableResult) {
                    let content = String(mutableResult[contentRange])
                    let converted = content.map { subMap[$0] ?? String($0) }.joined()
                    mutableResult.replaceSubrange(fullRange, with: converted)
                }
            }
            result = mutableResult
        }

        // Handle _x single char subscript
        let subSinglePattern = try? NSRegularExpression(pattern: #"_([0-9a-zA-Z])"#)
        if let subSinglePattern = subSinglePattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = subSinglePattern.matches(in: result, range: nsRange).reversed()
            var mutableResult = result
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: mutableResult),
                   let fullRange = Range(match.range, in: mutableResult) {
                    let ch = mutableResult[contentRange].first!
                    let converted = subMap[ch] ?? String(ch)
                    mutableResult.replaceSubrange(fullRange, with: converted)
                }
            }
            result = mutableResult
        }

        // Clean up remaining \text{...} → just the text
        let textPattern = try? NSRegularExpression(pattern: #"\\text\{([^}]+)\}"#)
        if let textPattern = textPattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = textPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1")
        }

        // Clean up remaining \mathrm{...}, \mathbf{...}, etc.
        let mathPattern = try? NSRegularExpression(pattern: #"\\math[a-z]+\{([^}]+)\}"#)
        if let mathPattern = mathPattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = mathPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1")
        }

        // Remove remaining backslash commands that we couldn't convert
        let cmdPattern = try? NSRegularExpression(pattern: #"\\[a-zA-Z]+"#)
        if let cmdPattern = cmdPattern {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = cmdPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "")
        }

        // Clean up braces
        result = result.replacingOccurrences(of: "{", with: "")
        result = result.replacingOccurrences(of: "}", with: "")

        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Block LaTeX View (WKWebView-based with KaTeX, only for display-mode formulas)

private struct BlockLaTeXView: View {
    let latex: String

    @State private var height: CGFloat = 40
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BlockLaTeXWebView(
            latex: latex,
            isDark: colorScheme == .dark,
            height: $height
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Block LaTeX WKWebView Wrapper

@MainActor
private struct BlockLaTeXWebView: UIViewRepresentable {
    let latex: String
    let isDark: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "sizeCallback")
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastKey = ""

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let key = "\(latex)-\(isDark)"
        guard key != context.coordinator.lastKey else { return }
        context.coordinator.lastKey = key

        // Encode LaTeX as JSON string for safe JS embedding
        let encoder = JSONEncoder()
        let jsonLatex: String
        if let jsonData = try? encoder.encode(latex),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            jsonLatex = jsonStr
        } else {
            jsonLatex = "\"\(latex.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }

        let textColor = isDark ? "#e5e5e5" : "#1c1c1e"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css" crossorigin="anonymous">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js" crossorigin="anonymous"></script>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: transparent;
            color: \(textColor);
            font-size: 17px;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 24px;
            padding: 0;
            -webkit-text-size-adjust: none;
        }
        .katex { font-size: 1em !important; }
        .katex-display { margin: 0 !important; }
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
                    displayMode: true,
                    throwOnError: false,
                    trust: true,
                    strict: false
                });
            } catch(e) {
                document.getElementById('math').textContent = latexStr;
            }
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

        webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var lastKey: String = ""

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
