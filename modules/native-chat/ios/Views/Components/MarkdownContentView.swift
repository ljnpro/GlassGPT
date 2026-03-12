import SwiftUI
import Foundation
@preconcurrency import WebKit

fileprivate enum InlineSegment: Sendable {
    case text(String)
    case latexInline(String)
}

fileprivate enum BlockPart: Identifiable, Sendable {
    case richText(id: Int, segments: [InlineSegment])
    case heading(id: Int, level: Int, text: String)
    case latexBlock(id: Int, content: String)
    case codeBlock(id: Int, language: String?, code: String)

    var id: Int {
        switch self {
        case let .richText(id, _):
            return id
        case let .heading(id, _, _):
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

    /// First pass: extract code blocks and LaTeX blocks from raw text.
    /// Returns a mix of code/latex blocks and raw text chunks.
    private func parseBlocks(_ input: String) -> [BlockPart] {
        var firstPass: [BlockPart] = []
        var inlineBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var i = 0
        var nextID = 0

        func makeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        // Flush accumulated inline text as a temporary richText block (will be refined in second pass)
        func flushInline() {
            if !inlineBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Placeholder: store raw text; we'll split into headings/richText in second pass
                let segments = parseInlineSegments(inlineBuffer)
                firstPass.append(.richText(id: makeID(), segments: segments))
            }
            inlineBuffer = ""
        }

        while i < count {
            // --- Code block ---
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
                    firstPass.append(.codeBlock(id: makeID(), language: lang.isEmpty ? nil : lang, code: code))
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

            // --- LaTeX block \[...\] ---
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
                        firstPass.append(.latexBlock(id: makeID(), content: latex))
                    }
                    i = end + 2
                } else {
                    inlineBuffer.append("\\[")
                    i = start
                }
                continue
            }

            // --- LaTeX block $$...$$ ---
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
                        firstPass.append(.latexBlock(id: makeID(), content: latex))
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

        if firstPass.isEmpty {
            return [.richText(id: 0, segments: [.text(input)])]
        }

        // Second pass: split richText blocks into headings and plain richText by line
        var finalParts: [BlockPart] = []
        for part in firstPass {
            switch part {
            case let .richText(_, segments):
                // Reconstruct the raw text from segments to do line-level parsing
                let rawText = segments.map { seg in
                    switch seg {
                    case let .text(str): return str
                    case let .latexInline(latex): return "$\(latex)$"
                    }
                }.joined()

                let lines = rawText.components(separatedBy: "\n")
                var lineBuffer: [String] = []

                func flushLineBuffer() {
                    let joined = lineBuffer.joined(separator: "\n")
                    if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let segs = parseInlineSegments(joined)
                        finalParts.append(.richText(id: makeID(), segments: segs))
                    }
                    lineBuffer = []
                }

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Detect heading: must start with # followed by space
                    if let headingMatch = detectHeading(trimmed) {
                        flushLineBuffer()
                        finalParts.append(.heading(id: makeID(), level: headingMatch.level, text: headingMatch.text))
                    } else {
                        lineBuffer.append(line)
                    }
                }
                flushLineBuffer()

            default:
                finalParts.append(part)
            }
        }

        // Re-assign IDs sequentially
        var result: [BlockPart] = []
        var finalID = 0
        for part in finalParts {
            switch part {
            case let .richText(_, segments):
                result.append(.richText(id: finalID, segments: segments))
            case let .heading(_, level, text):
                result.append(.heading(id: finalID, level: level, text: text))
            case let .latexBlock(_, content):
                result.append(.latexBlock(id: finalID, content: content))
            case let .codeBlock(_, language, code):
                result.append(.codeBlock(id: finalID, language: language, code: code))
            }
            finalID += 1
        }

        return result.isEmpty ? [.richText(id: 0, segments: [.text(input)])] : result
    }

    /// Detect a Markdown heading line. Returns (level, text) or nil.
    private func detectHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        let chars = Array(line)
        while level < chars.count && level < 6 && chars[level] == "#" {
            level += 1
        }
        guard level > 0 else { return nil }
        // Must be followed by a space (or be the entire line)
        guard level < chars.count && chars[level] == " " else { return nil }
        let text = String(chars[(level + 1)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
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
            ForEach(Array(blockParts.enumerated()), id: \.element.id) { index, part in
                blockView(for: part, at: index)
            }
        }
    }

    @ViewBuilder
    private func blockView(for part: BlockPart, at index: Int) -> some View {
        switch part {
        case let .codeBlock(id: id, language: language, code: code):
            CodeBlockView(language: language, code: code)
                .id(id)

        case let .latexBlock(id: id, content: content):
            let prevIsLatex = index > 0 && isLatexBlock(blockParts[index - 1])
            let nextIsLatex = index + 1 < blockParts.count && isLatexBlock(blockParts[index + 1])
            BlockLaTeXView(latex: content)
                .id(id)
                // Tighten spacing to surrounding text, but keep normal spacing between consecutive LaTeX blocks
                .padding(.top, prevIsLatex ? 8 : -2)
                .padding(.bottom, nextIsLatex ? 8 : -2)

        case let .heading(id: id, level: level, text: text):
            HeadingView(level: level, text: text)
                .id(id)

        case let .richText(id: id, segments: segments):
            RichTextView(segments: segments)
                .id(id)
        }
    }

    private func isLatexBlock(_ part: BlockPart) -> Bool {
        if case .latexBlock = part { return true }
        return false
    }
}

// MARK: - Heading View

private struct HeadingView: View {
    let level: Int
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
                .font(fontForLevel)
                .fontWeight(weightForLevel)
                .textSelection(.enabled)
                .padding(.top, topPadding)
                .padding(.bottom, 2)
        } else {
            Text(text)
                .font(fontForLevel)
                .fontWeight(weightForLevel)
                .textSelection(.enabled)
                .padding(.top, topPadding)
                .padding(.bottom, 2)
        }
    }

    private var fontForLevel: Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        default: return .subheadline
        }
    }

    private var weightForLevel: Font.Weight {
        switch level {
        case 1: return .bold
        case 2: return .bold
        case 3: return .semibold
        case 4: return .semibold
        default: return .medium
        }
    }

    private var topPadding: CGFloat {
        switch level {
        case 1: return 12
        case 2: return 10
        case 3: return 8
        default: return 6
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

        let attributed = robustMarkdownParse(combinedText)
        Text(attributed)
            .font(.body)
            .textSelection(.enabled)
    }

    /// Robust Markdown parser that handles bold/italic even when Apple's
    /// CommonMark parser fails (e.g. CJK text with punctuation after **).
    ///
    /// Strategy: first try Apple's parser. If the result still contains
    /// literal `**` or `*` markers, fall back to manual regex-based parsing.
    private func robustMarkdownParse(_ text: String) -> AttributedString {
        // Try Apple's parser first
        if let appleResult = try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            // Check if Apple's parser actually processed the bold markers
            let plainText = String(appleResult.characters)
            if !plainText.contains("**") {
                return appleResult
            }
        }

        // Fallback: manual parsing for bold and italic
        return manualMarkdownParse(text)
    }

    /// Manually parse **bold**, __bold__, *italic*, _italic_, `code`,
    /// and ***bold italic*** markers into an AttributedString.
    private func manualMarkdownParse(_ text: String) -> AttributedString {
        // We'll work with NSMutableAttributedString for easier range manipulation
        var working = text

        // Collect styled ranges: (range in final string, isBold, isItalic, isCode)
        struct StyledRange {
            let range: Range<String.Index>
            let isBold: Bool
            let isItalic: Bool
            let isCode: Bool
        }

        var result = AttributedString()

        // Process the text character by character, handling markers
        let chars = Array(working)
        let count = chars.count
        var i = 0
        var currentText = ""
        var isBold = false
        var isItalic = false
        var isCode = false

        func flushCurrent() {
            if !currentText.isEmpty {
                var chunk = AttributedString(currentText)
                if isBold && isItalic {
                    chunk.font = .body.bold().italic()
                } else if isBold {
                    chunk.font = .body.bold()
                } else if isItalic {
                    chunk.font = .body.italic()
                } else if isCode {
                    chunk.font = .body.monospaced()
                    chunk.backgroundColor = .secondary.opacity(0.12)
                } else {
                    chunk.font = .body
                }
                result += chunk
                currentText = ""
            }
        }

        while i < count {
            // Inline code: `...`
            if chars[i] == "`" && !isCode {
                // Find closing backtick
                var end = i + 1
                while end < count && chars[end] != "`" { end += 1 }
                if end < count {
                    flushCurrent()
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
                // Find closing ***
                var end = i + 3
                while end + 2 < count {
                    if chars[end] == "*" && chars[end + 1] == "*" && chars[end + 2] == "*" { break }
                    end += 1
                }
                if end + 2 < count {
                    flushCurrent()
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
                // Find closing marker
                var end = i + 2
                while end + 1 < count {
                    if chars[end] == marker && chars[end + 1] == marker { break }
                    end += 1
                }
                if end + 1 < count {
                    flushCurrent()
                    let content = String(chars[(i + 2)..<end])
                    // Recursively parse the content for nested italic
                    var chunk = AttributedString(content)
                    chunk.font = .body.bold()
                    result += chunk
                    i = end + 2
                    continue
                }
            }

            // Italic: *...* or _..._  (single marker, not followed by another)
            if (chars[i] == "*" || chars[i] == "_") {
                let marker = chars[i]
                // Make sure it's not ** or __
                if i + 1 < count && chars[i + 1] != marker {
                    var end = i + 1
                    while end < count {
                        if chars[end] == marker && (end + 1 >= count || chars[end + 1] != marker) { break }
                        end += 1
                    }
                    if end < count {
                        flushCurrent()
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

        flushCurrent()
        return result
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

// MARK: - Block LaTeX View

private struct BlockLaTeXView: View {
    let latex: String

    @State private var height: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        BlockLaTeXWebView(
            latex: latex,
            isDark: colorScheme == .dark,
            height: $height
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .center)
        .clipped()
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

        let result = KaTeXProvider.htmlForLatex(latex, isDark: isDark)
        webView.loadHTMLString(result.html, baseURL: result.baseURL)
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
