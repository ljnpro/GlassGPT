import SwiftUI

// MARK: - Thinking Indicator (capsule shown while model is actively reasoning, before text arrives)

struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating)

            Text("Reasoning…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: Capsule())
    }
}

// MARK: - Thinking View (card-style, collapsible reasoning text with Markdown rendering)

struct ThinkingView: View {
    let text: String
    /// Whether the thinking is still in progress (streaming). When true, starts expanded.
    var isLive: Bool = false
    /// Optional external binding for expanded state (used during streaming to preserve state across re-renders)
    @Binding var externalIsExpanded: Bool?

    @State private var internalIsExpanded: Bool = false
    @State private var hasInitialized: Bool = false

    /// Use external binding if provided, otherwise fall back to internal state
    private var isExpanded: Bool {
        get { externalIsExpanded ?? internalIsExpanded }
    }

    private func setExpanded(_ value: Bool) {
        if externalIsExpanded != nil {
            externalIsExpanded = value
        } else {
            internalIsExpanded = value
        }
    }

    init(text: String, isLive: Bool = false, externalIsExpanded: Binding<Bool?> = .constant(nil)) {
        self.text = text
        self.isLive = isLive
        self._externalIsExpanded = externalIsExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, tappable to toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    setExpanded(!isExpanded)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isLive ? "brain" : "brain.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse, options: .repeating, isActive: isLive)

                    Text(isLive ? "Reasoning…" : "Reasoning Completed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Expandable content — Markdown-rendered thinking text
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ThinkingMarkdownText(text: text)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .onAppear {
            if !hasInitialized {
                hasInitialized = true
                // Live (streaming) thinking starts expanded; completed thinking starts collapsed
                setExpanded(isLive)
            }
        }
        .onChange(of: isLive) { _, newValue in
            // When streaming finishes, auto-collapse
            if !newValue && isExpanded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    setExpanded(false)
                }
            }
        }
    }
}

// MARK: - Thinking Markdown Text (renders bold, italic, code, etc.)

private struct ThinkingMarkdownText: View {
    let text: String

    var body: some View {
        let attributed = robustMarkdownParse(text)
        Text(attributed)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .textSelection(.enabled)
    }

    /// Robust Markdown parser: try Apple's parser first, fall back to manual
    /// parsing if the result still contains literal `**` markers.
    private func robustMarkdownParse(_ text: String) -> AttributedString {
        if let appleResult = try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            let plainText = String(appleResult.characters)
            if !plainText.contains("**") {
                return appleResult
            }
        }
        return manualMarkdownParse(text)
    }

    /// Manual inline Markdown parser for bold, italic, bold+italic, and inline code.
    private func manualMarkdownParse(_ text: String) -> AttributedString {
        var result = AttributedString()
        let chars = Array(text)
        let count = chars.count
        var i = 0
        var currentText = ""

        func flushPlain() {
            if !currentText.isEmpty {
                var chunk = AttributedString(currentText)
                chunk.font = .caption
                result += chunk
                currentText = ""
            }
        }

        while i < count {
            // Inline code: `...`
            if chars[i] == "`" {
                var end = i + 1
                while end < count && chars[end] != "`" { end += 1 }
                if end < count {
                    flushPlain()
                    let codeContent = String(chars[(i + 1)..<end])
                    var chunk = AttributedString(codeContent)
                    chunk.font = .caption.monospaced()
                    result += chunk
                    i = end + 1
                    continue
                }
            }

            // Bold+Italic: ***...***
            if i + 2 < count && chars[i] == "*" && chars[i + 1] == "*" && chars[i + 2] == "*" {
                var end = i + 3
                while end + 2 < count {
                    if chars[end] == "*" && chars[end + 1] == "*" && chars[end + 2] == "*" { break }
                    end += 1
                }
                if end + 2 < count {
                    flushPlain()
                    let content = String(chars[(i + 3)..<end])
                    var chunk = AttributedString(content)
                    chunk.font = .caption.bold().italic()
                    result += chunk
                    i = end + 3
                    continue
                }
            }

            // Bold: **...**
            if i + 1 < count && chars[i] == "*" && chars[i + 1] == "*" {
                var end = i + 2
                while end + 1 < count {
                    if chars[end] == "*" && chars[end + 1] == "*" { break }
                    end += 1
                }
                if end + 1 < count {
                    flushPlain()
                    let content = String(chars[(i + 2)..<end])
                    var chunk = AttributedString(content)
                    chunk.font = .caption.bold()
                    result += chunk
                    i = end + 2
                    continue
                }
            }

            // Italic: *...*
            if chars[i] == "*" {
                if i + 1 < count && chars[i + 1] != "*" {
                    var end = i + 1
                    while end < count {
                        if chars[end] == "*" && (end + 1 >= count || chars[end + 1] != "*") { break }
                        end += 1
                    }
                    if end < count {
                        flushPlain()
                        let content = String(chars[(i + 1)..<end])
                        var chunk = AttributedString(content)
                        chunk.font = .caption.italic()
                        result += chunk
                        i = end + 1
                        continue
                    }
                }
            }

            currentText.append(chars[i])
            i += 1
        }

        flushPlain()
        return result
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(8)
        .onAppear { animating = true }
    }
}
