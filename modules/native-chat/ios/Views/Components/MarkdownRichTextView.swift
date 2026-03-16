import Foundation
import SwiftUI

struct RichTextView: View {
    let segments: [InlineSegment]
    var filePathAnnotations: [FilePathAnnotation] = []
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?

    var body: some View {
        let combinedText = segments.map { segment in
            switch segment {
            case let .text(str):
                return str
            case let .latexInline(latex):
                return latexToUnicode(latex)
            }
        }.joined()

        let attributed = RichTextAttributedStringBuilder.parseRichText(combinedText)
        Text(attributed)
            .font(.body)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "sandbox" {
                    let sandboxPath = url.absoluteString
                    let annotation = findFilePathAnnotation(for: sandboxPath)
                    onSandboxLinkTap?(sandboxPath, annotation)
                    return .handled
                }
                return .systemAction
            })
    }

    func findFilePathAnnotation(for sandboxURL: String) -> FilePathAnnotation? {
        if let exact = filePathAnnotations.first(where: { $0.sandboxPath == sandboxURL }) {
            return exact
        }

        let pathOnly: String
        if sandboxURL.hasPrefix("sandbox:") {
            pathOnly = String(sandboxURL.dropFirst("sandbox:".count))
        } else {
            pathOnly = sandboxURL
        }

        if let match = filePathAnnotations.first(where: {
            $0.sandboxPath == pathOnly ||
            $0.sandboxPath.hasSuffix(pathOnly) ||
            pathOnly.hasSuffix($0.sandboxPath)
        }) {
            return match
        }

        let filename = (pathOnly as NSString).lastPathComponent
        if !filename.isEmpty {
            if let match = filePathAnnotations.first(where: {
                ($0.sandboxPath as NSString).lastPathComponent == filename ||
                $0.filename == filename
            }) {
                return match
            }
        }

        if filePathAnnotations.count == 1 {
            return filePathAnnotations.first
        }

        return nil
    }

    func latexToUnicode(_ latex: String) -> String {
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

        if let vecPattern = makeRegex(#"\\vec\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = vecPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1\u{20D7}")
        }

        if let arrowPattern = makeRegex(#"\\overrightarrow\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = arrowPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1\u{20D7}")
        }

        if let fracPattern = makeRegex(#"\\frac\{([^}]+)\}\{([^}]+)\}"#) {
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

        if let supPattern = makeRegex(#"\^\{([^}]+)\}"#) {
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

        if let supSinglePattern = makeRegex(#"\^([0-9a-zA-Z])"#) {
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

        if let subPattern = makeRegex(#"_\{([^}]+)\}"#) {
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

        if let subSinglePattern = makeRegex(#"_([0-9a-zA-Z])"#) {
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

        if let textPattern = makeRegex(#"\\text\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = textPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1")
        }

        if let mathPattern = makeRegex(#"\\math[a-zA-Z]+\{([^}]+)\}"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = mathPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "$1")
        }

        if let cmdPattern = makeRegex(#"\\[a-zA-Z]+"#) {
            let nsRange = NSRange(result.startIndex..., in: result)
            result = cmdPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: "")
        }

        result = result.replacingOccurrences(of: "{", with: "")
        result = result.replacingOccurrences(of: "}", with: "")

        return result.trimmingCharacters(in: .whitespaces)
    }

    private func makeRegex(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            return nil
        }
    }
}
