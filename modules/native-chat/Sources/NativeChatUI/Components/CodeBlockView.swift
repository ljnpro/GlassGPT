import ChatUIComponents
import SwiftUI
import UIKit

@MainActor
/// Renders a fenced code block with a language header, copy button, and syntax highlighting.
package struct CodeBlockView: View {
    /// Controls whether the code block renders its own glass surface or relies on a parent container.
    package enum SurfaceStyle {
        /// Renders with its own rounded glass border.
        case standalone
        /// Renders without a border, intended for embedding inside another surface.
        case embedded
    }

    /// The programming language label, if specified.
    let language: String?
    /// The raw code string to display.
    let code: String
    /// The surface rendering style.
    var surfaceStyle: SurfaceStyle = .standalone

    /// Creates a code block view for the given language and code.
    package init(
        language: String?,
        code: String,
        surfaceStyle: SurfaceStyle = .standalone
    ) {
        self.language = language
        self.code = code
        self.surfaceStyle = surfaceStyle
    }

    @State private var isCopied = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.hapticsEnabled) private var hapticsEnabled

    package var body: some View {
        Group {
            switch surfaceStyle {
            case .standalone:
                chrome
                    .padding(10)
                    .singleSurfaceGlass(
                        cornerRadius: 16,
                        stableFillOpacity: 0.01,
                        tintOpacity: 0.024,
                        borderWidth: 0.8,
                        darkBorderOpacity: 0.15,
                        lightBorderOpacity: 0.085
                    )

            case .embedded:
                chrome
            }
        }
    }

    private var hapticService: HapticService {
        HapticService()
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let languageTitle {
                    Text(languageTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.2)

                    Spacer(minLength: 8)
                } else {
                    Spacer()
                }

                Button {
                    UIPasteboard.general.string = code
                    withAnimation(.spring(duration: 0.3)) {
                        isCopied = true
                    }
                    Task {
                        do {
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                        } catch is CancellationError {
                            // Preserve the previous swallowed-error behavior by continuing immediately.
                        }
                        withAnimation(.spring(duration: 0.3)) {
                            isCopied = false
                        }
                    }
                    hapticService.impact(.light, isEnabled: hapticsEnabled)
                } label: {
                    Label(
                        isCopied ? "Copied" : "Copy",
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .singleFrameGlassCapsuleControl(
                        tintOpacity: 0.015,
                        borderWidth: 0.75,
                        darkBorderOpacity: 0.14,
                        lightBorderOpacity: 0.08
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCopied ? "Code copied" : "Copy code")
                .accessibilityIdentifier("codeBlock.copy")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .frame(minHeight: 24)
            .background(headerFill)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(borderColor.opacity(0.5))
                    .frame(height: 0.5)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedCode)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .textSelection(.enabled)
            }
        }
    }

    private var headerFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.035)
            : Color.black.opacity(0.028)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    private var languageTitle: String? {
        guard let language, !language.isEmpty else { return nil }

        switch language.lowercased() {
        case "latex":
            return "LaTeX"
        case "swift":
            return "Swift"
        case "python":
            return "Python"
        case "javascript", "js":
            return "JavaScript"
        case "typescript", "ts":
            return "TypeScript"
        case "json":
            return "JSON"
        default:
            return language.uppercased()
        }
    }

    // MARK: - Native Syntax Highlighting

    private var highlightedCode: AttributedString {
        var result = AttributedString(code)
        let isDark = colorScheme == .dark

        // Colors matching popular code themes
        let keywordColor: Color = isDark ? .init(red: 0.78, green: 0.56, blue: 0.87) : .init(red: 0.61, green: 0.15, blue: 0.69)
        let stringColor: Color = isDark ? .init(red: 0.59, green: 0.80, blue: 0.53) : .init(red: 0.15, green: 0.55, blue: 0.13)
        let commentColor: Color = isDark ? .init(red: 0.50, green: 0.55, blue: 0.60) : .init(red: 0.42, green: 0.47, blue: 0.52)
        let numberColor: Color = isDark ? .init(red: 0.82, green: 0.68, blue: 0.47) : .init(red: 0.75, green: 0.49, blue: 0.07)
        let typeColor: Color = isDark ? .init(red: 0.90, green: 0.80, blue: 0.55) : .init(red: 0.60, green: 0.40, blue: 0.10)
        let funcColor: Color = isDark ? .init(red: 0.38, green: 0.73, blue: 0.93) : .init(red: 0.07, green: 0.44, blue: 0.73)

        // Apply highlighting patterns
        applyPattern(&result, pattern: #"//[^\n]*"#, color: commentColor)
        applyPattern(&result, pattern: #"/\*[\s\S]*?\*/"#, color: commentColor)
        applyPattern(&result, pattern: #"#[^\n]*"#, color: commentColor) // Python/shell comments
        applyPattern(&result, pattern: #""(?:[^"\\]|\\.)*""#, color: stringColor)
        applyPattern(&result, pattern: #"'(?:[^'\\]|\\.)*'"#, color: stringColor)
        applyPattern(&result, pattern: #"`(?:[^`\\]|\\.)*`"#, color: stringColor)

        // Keywords (common across languages)
        let keywords = [
            "func", "var", "let", "const", "class", "struct", "enum", "protocol", "extension",
            "import", "return", "if", "else", "for", "while", "do", "switch", "case", "default",
            "break", "continue", "guard", "self", "Self", "super", "init", "deinit", "throw",
            "throws", "try", "catch", "async", "await", "public", "private", "internal", "open",
            "static", "final", "override", "mutating", "nonmutating", "lazy", "weak", "unowned",
            "true", "false", "nil", "null", "undefined", "void", "some", "any", "where", "in",
            "is", "as", "new", "delete", "typeof", "instanceof", "export", "from", "type",
            "interface", "implements", "extends", "abstract", "def", "lambda", "yield", "with",
            "pass", "raise", "except", "finally", "print", "println", "main", "package",
            "fn", "pub", "mod", "use", "crate", "impl", "trait", "match", "ref", "mut",
            "@Observable", "@MainActor", "@State", "@Binding", "@Environment", "@Published",
            "@objc", "@available", "@discardableResult", "@escaping", "@Sendable"
        ]
        let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
        applyPattern(&result, pattern: keywordPattern, color: keywordColor)

        // Numbers
        applyPattern(&result, pattern: #"\b\d+(\.\d+)?\b"#, color: numberColor)

        // Type names (capitalized words)
        applyPattern(&result, pattern: #"\b[A-Z][a-zA-Z0-9]+\b"#, color: typeColor)

        // Function calls
        applyPattern(&result, pattern: #"\b[a-z_][a-zA-Z0-9_]*(?=\s*\()"#, color: funcColor)

        return result
    }

    private func applyPattern(_ text: inout AttributedString, pattern: String, color: Color) {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return
        }
        let nsString = String(text.characters[...])
        let nsRange = NSRange(location: 0, length: nsString.utf16.count)
        let matches = regex.matches(in: nsString, range: nsRange)

        for match in matches {
            guard let swiftRange = Range(match.range, in: nsString) else { continue }
            let lower = AttributedString.Index(swiftRange.lowerBound, within: text)
            let upper = AttributedString.Index(swiftRange.upperBound, within: text)
            guard let lower, let upper else { continue }
            text[lower..<upper].foregroundColor = color
        }
    }
}
