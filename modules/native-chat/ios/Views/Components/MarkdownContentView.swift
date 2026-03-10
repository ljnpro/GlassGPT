import SwiftUI
import Foundation
@preconcurrency import WebKit

fileprivate enum InlineSegment: Sendable {
    case text(String)
    case latexInline(String)
}

fileprivate enum BlockPart: Identifiable, Sendable {
    case richText(id: Int, segments: [InlineSegment])
    case latexBlock(id: Int, content: String)
    case codeBlock(id: Int, language: String?, code: String)

    var id: Int {
        switch self {
        case let .richText(id, _):
            return id
        case let .latexBlock(id, _):
            return id
        case let .codeBlock(id, _, _):
            return id
        }
    }
}

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let text: String

    private var blockParts: [BlockPart] {
        parseBlocks(text)
    }

    private func parseBlocks(_ input: String) -> [BlockPart] {
        var parts: [BlockPart] = []
        var inlineBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var i = 0
        var nextID = 0

        func makeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        func flushInline() {
            if !inlineBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let segments = parseInlineSegments(inlineBuffer)
                parts.append(.richText(id: makeID(), segments: segments))
            }
            inlineBuffer = ""
        }

        while i < count {
            if i + 2 < count && chars[i] == "`" && chars[i + 1] == "`" && chars[i + 2] == "`" {
                flushInline()
                let start = i + 3
                var langEnd = start
                while langEnd < count && chars[langEnd] != "\n" {
                    langEnd += 1
                }

                let lang = String(chars[start..<langEnd]).trimmingCharacters(in: .whitespaces)
                let codeStart = min(langEnd + 1, count)

                var codeEnd = codeStart
                var found = false
                while codeEnd + 2 < count {
                    if chars[codeEnd] == "`" && chars[codeEnd + 1] == "`" && chars[codeEnd + 2] == "`" {
                        found = true
                        break
                    }
                    codeEnd += 1
                }

                if found {
                    let code = String(chars[codeStart..<codeEnd])
                    parts.append(.codeBlock(id: makeID(), language: lang.isEmpty ? nil : lang, code: code))
                    i = codeEnd + 3
                    if i < count && chars[i] == "\n" {
                        i += 1
                    }
                } else {
                    inlineBuffer += "```"
                    i = start
                }
                continue
            }

            if i + 1 < count && chars[i] == "\\" && chars[i + 1] == "[" {
                flushInline()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\" && chars[end + 1] == "]" {
                        found = true
                        break
                    }
                    end += 1
                }

                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        parts.append(.latexBlock(id: makeID(), content: latex))
                    }
                    i = end + 2
                } else {
                    inlineBuffer.append("\\[")
                    i = start
                }
                continue
            }

            if i + 1 < count && chars[i] == "$" && chars[i + 1] == "$" {
                flushInline()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "$" && chars[end + 1] == "$" {
                        found = true
                        break
                    }
                    end += 1
                }

                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        parts.append(.latexBlock(id: makeID(), content: latex))
                    }
                    i = end + 2
                } else {
                    inlineBuffer.append("$$")
                    i = start
                }
                continue
            }

            inlineBuffer.append(chars[i])
            i += 1
        }

        flushInline()

        if parts.isEmpty {
            return [.richText(id: 0, segments: [.text(input)])]
        }

        return parts
    }

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
            if i + 1 < count && chars[i] == "\\" && chars[i + 1] == "(" {
                flushText()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\" && chars[end + 1] == ")" {
                        found = true
                        break
                    }
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

            if chars[i] == "$" && (i == 0 || chars[i - 1] != "\\") {
                let start = i + 1
                var end = start
                var found = false
                while end < count && chars[end] != "\n" {
                    if chars[end] == "$" && (end == start || chars[end - 1] != "\\") {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(blockParts, id: \.id) { part in
                blockView(for: part)
            }
        }
    }

    @ViewBuilder
    private func blockView(for part: BlockPart) -> some View {
        switch part {
        case let .codeBlock(id: id, language: language, code: code):
            CodeBlockView(language: language, code: code)
                .id(id)

        case let .latexBlock(id: id, content: content):
            BlockLaTeXView(latex: content)
                .padding(.vertical, 2)
                .id(id)

        case let .richText(id: id, segments: segments):
            RichTextView(segments: segments)
                .id(id)
        }
    }
}

// MARK: - Rich Text View

private struct RichTextView: View {
    let segments: [InlineSegment]

    var body: some View {
        let combinedText = segments.map { segment in
            switch segment {
            case let .text(str):
                return str
            case let .latexInline(latex):
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

    private func latexToUnicode(_ latex: String) -> String {
        var result = latex

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
            ("\\Phi", "Φ"), ("\\Psi", "Ψ"), ("\\Omega", "Ω")
        ]

        for (cmd, unicode) in greekMap {
            result = result.replacingOccurrences(of: cmd, with: unicode)
        }

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
            ("\\vec{", ""), ("\\overrightarrow{", "")
        ]

        for (cmd, unicode) in symbolMap where !cmd.hasSuffix("{") {
            result = result.replacingOccurrences(of: cmd, with: unicode)
        }

        if let vecPattern = try? NSRegularExpression(pattern: #"\\vec\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = vecPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1\u{20D7}")
        }

        if let arrowPattern = try? NSRegularExpression(pattern: #"\\overrightarrow\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = arrowPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1\u{20D7}")
        }

        if let fracPattern = try? NSRegularExpression(pattern: #"\\frac\{([^}]+)\}\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = fracPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1/$2")
        }

        let subMap: [Character: String] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
            "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
            "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
            "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
            "v": "ᵥ", "x": "ₓ"
        ]

        let supMap: [Character: String] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
            "n": "ⁿ", "i": "ⁱ",
            "+": "⁺", "-": "⁻", "(": "⁽", ")": "⁾"
        ]

        if let supPattern = try? NSRegularExpression(pattern: #"\^\{([^}]+)\}"#) {
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

        if let supSinglePattern = try? NSRegularExpression(pattern: #"\^([0-9a-zA-Z])"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = supSinglePattern.matches(in: result, range: nsRange).reversed()
            var mutableResult = result
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: mutableResult),
                   let fullRange = Range(match.range, in: mutableResult),
                   let ch = mutableResult[contentRange].first {
                    let converted = supMap[ch] ?? String(ch)
                    mutableResult.replaceSubrange(fullRange, with: converted)
                }
            }
            result = mutableResult
        }

        if let subPattern = try? NSRegularExpression(pattern: #"_\{([^}]+)\}"#) {
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

        if let subSinglePattern = try? NSRegularExpression(pattern: #"_([0-9a-zA-Z])"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = subSinglePattern.matches(in: result, range: nsRange).reversed()
            var mutableResult = result
            for match in matches {
                if let contentRange = Range(match.range(at: 1), in: mutableResult),
                   let fullRange = Range(match.range, in: mutableResult),
                   let ch = mutableResult[contentRange].first {
                    let converted = subMap[ch] ?? String(ch)
                    mutableResult.replaceSubrange(fullRange, with: converted)
                }
            }
            result = mutableResult
        }

        if let textPattern = try? NSRegularExpression(pattern: #"\\text\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = textPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1")
        }

        if let mathPattern = try? NSRegularExpression(pattern: #"\\math[a-zA-Z]+\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = mathPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1")
        }

        if let cmdPattern = try? NSRegularExpression(pattern: #"\\[a-zA-Z]+"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = cmdPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "")
        }

        result = result.replacingOccurrences(of: "{", with: "")
        result = result.replacingOccurrences(of: "}", with: "")

        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Code Block View

private struct CodeBlockView: View {
    let language: String?
    let code: String

    private var displayCode: String {
        code.trimmingCharacters(in: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(displayCode.isEmpty ? " " : displayCode)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .padding(.vertical, 2)
    }
}

// MARK: - Block LaTeX View

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

        let encoder = JSONEncoder()
        let jsonLatex: String
        if let jsonData = try? encoder.encode(latex),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            jsonLatex = jsonString
        } else {
            let escaped = latex
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            jsonLatex = "\"\(escaped)\""
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

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "sizeCallback")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, @unchecked Sendable {
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
            if let value = message.body as? CGFloat {
                newHeight = max(value, 20)
            } else if let value = message.body as? Int {
                newHeight = max(CGFloat(value), 20)
            } else if let value = message.body as? Double {
                newHeight = max(CGFloat(value), 20)
            } else {
                return
            }

            Task { @MainActor in
                self.height = newHeight
            }
        }
    }
}
