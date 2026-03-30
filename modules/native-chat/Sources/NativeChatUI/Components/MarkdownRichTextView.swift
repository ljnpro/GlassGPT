import ChatDomain
import ChatUIComponents
import ConversationSurfaceLogic
import Foundation
import GeneratedFilesCore
import SwiftUI

/// Renders inline segments (text and inline LaTeX converted to Unicode) as rich attributed text with link handling.
package struct RichTextView: View {
    let segments: [InlineSegment]
    var filePathAnnotations: [FilePathAnnotation] = []
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?

    /// Creates a rich text view with inline segments and optional sandbox link handling.
    package init(
        segments: [InlineSegment],
        filePathAnnotations: [FilePathAnnotation] = [],
        onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)? = nil
    ) {
        self.segments = segments
        self.filePathAnnotations = filePathAnnotations
        self.onSandboxLinkTap = onSandboxLinkTap
    }

    /// The attributed rich-text rendering of the combined inline segments.
    package var body: some View {
        let combinedText = segments.map { segment in
            switch segment {
            case let .text(str):
                str
            case let .latexInline(latex):
                latexToUnicode(latex)
            }
        }.joined()

        let attributed = RichTextAttributedStringBuilder.parseRichText(combinedText)
        Text(attributed)
            .font(.body)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "sandbox" {
                    guard let onSandboxLinkTap else {
                        return .discarded
                    }
                    let sandboxPath = url.absoluteString
                    let annotation = findFilePathAnnotation(for: sandboxPath)
                    onSandboxLinkTap(sandboxPath, annotation)
                    return .handled
                }
                return .systemAction
            })
    }

    /// Looks up a ``FilePathAnnotation`` matching the given sandbox URL using progressively looser matching.
    package func findFilePathAnnotation(for sandboxURL: String) -> FilePathAnnotation? {
        GeneratedFileAnnotationMatcher().findMatchingFilePathAnnotation(
            in: filePathAnnotations,
            sandboxURL: sandboxURL,
            fallback: nil
        )
    }

    /// Converts a LaTeX expression to a best-effort Unicode approximation for inline display.
    /// Converts inline LaTeX markup to a best-effort Unicode representation.
    package func latexToUnicode(_ latex: String) -> String {
        var result = latex

        applyLiteralReplacements(Self.greekReplacements, to: &result)
        applyLiteralReplacements(Self.symbolReplacements, to: &result)
        applyRegexReplacement(#"\\vec\{([^}]+)\}"#, template: "$1\u{20D7}", to: &result)
        applyRegexReplacement(#"\\overrightarrow\{([^}]+)\}"#, template: "$1\u{20D7}", to: &result)
        applyRegexReplacement(#"\\frac\{([^}]+)\}\{([^}]+)\}"#, template: "$1/$2", to: &result)
        applyGroupedScriptReplacement(#"\^\{([^}]+)\}"#, map: Self.superscriptMap, to: &result)
        applySingleScriptReplacement(#"\^([0-9a-zA-Z])"#, map: Self.superscriptMap, to: &result)
        applyGroupedScriptReplacement(#"_\{([^}]+)\}"#, map: Self.subscriptMap, to: &result)
        applySingleScriptReplacement(#"_([0-9a-zA-Z])"#, map: Self.subscriptMap, to: &result)
        applyRegexReplacement(#"\\text\{([^}]+)\}"#, template: "$1", to: &result)
        applyRegexReplacement(#"\\math[a-zA-Z]+\{([^}]+)\}"#, template: "$1", to: &result)
        applyRegexReplacement(#"\\[a-zA-Z]+"#, template: "", to: &result)
        result.removeAll(where: { $0 == "{" || $0 == "}" })

        return result.trimmingCharacters(in: .whitespaces)
    }

    private func makeRegex(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            return nil
        }
    }

    private func applyLiteralReplacements(
        _ replacements: [(String, String)],
        to value: inout String
    ) {
        for (command, unicode) in replacements {
            value = value.replacingOccurrences(of: command, with: unicode)
        }
    }

    private func applyRegexReplacement(
        _ pattern: String,
        template: String,
        to value: inout String
    ) {
        guard let regex = makeRegex(pattern) else {
            return
        }

        let nsRange = NSRange(value.startIndex..., in: value)
        value = regex.stringByReplacingMatches(in: value, range: nsRange, withTemplate: template)
    }

    private func applyGroupedScriptReplacement(
        _ pattern: String,
        map: [Character: String],
        to value: inout String
    ) {
        applyScriptReplacement(
            pattern,
            to: &value
        ) { mutableValue, match in
            guard let contentRange = Range(match.range(at: 1), in: mutableValue),
                  let fullRange = Range(match.range, in: mutableValue)
            else {
                return
            }

            let content = String(mutableValue[contentRange])
            let converted = content.map { map[$0] ?? String($0) }.joined()
            mutableValue.replaceSubrange(fullRange, with: converted)
        }
    }

    private func applySingleScriptReplacement(
        _ pattern: String,
        map: [Character: String],
        to value: inout String
    ) {
        applyScriptReplacement(
            pattern,
            to: &value
        ) { mutableValue, match in
            guard let contentRange = Range(match.range(at: 1), in: mutableValue),
                  let fullRange = Range(match.range, in: mutableValue),
                  let character = mutableValue[contentRange].first
            else {
                return
            }

            let converted = map[character] ?? String(character)
            mutableValue.replaceSubrange(fullRange, with: converted)
        }
    }

    private func applyScriptReplacement(
        _ pattern: String,
        to value: inout String,
        replacer: (inout String, NSTextCheckingResult) -> Void
    ) {
        guard let regex = makeRegex(pattern) else {
            return
        }

        let nsRange = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: nsRange).reversed()
        var mutableValue = value
        for match in matches {
            replacer(&mutableValue, match)
        }
        value = mutableValue
    }
}

private extension RichTextView {
    static let greekReplacements: [(String, String)] = [
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

    static let symbolReplacements: [(String, String)] = [
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
        ("\\ldots", "…"), ("\\cdots", "⋯"), ("\\vdots", "⋮")
    ]

    static let subscriptMap: [Character: String] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
        "v": "ᵥ", "x": "ₓ"
    ]

    static let superscriptMap: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "n": "ⁿ", "i": "ⁱ",
        "+": "⁺", "-": "⁻", "(": "⁽", ")": "⁾"
    ]
}
