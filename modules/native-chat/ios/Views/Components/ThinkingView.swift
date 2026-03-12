import SwiftUI

// MARK: - Thinking Indicator (shown while model is actively reasoning)

struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.caption)
                .symbolEffect(.breathe)
                .foregroundStyle(.purple)

            Text("Thinking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)

            // Animated dots
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.purple.opacity(0.6))
                        .frame(width: 5, height: 5)
                        .scaleEffect(animating ? 1.0 : 0.4)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: animating
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.purple.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.purple.opacity(0.15), lineWidth: 1)
        )
        .onAppear { animating = true }
    }
}

// MARK: - Thinking View (collapsible reasoning text with Markdown rendering)

struct ThinkingView: View {
    let text: String
    /// Whether the thinking is still in progress (streaming). When true, starts expanded.
    var isLive: Bool = false

    @State private var isExpanded: Bool = false
    @State private var hasInitialized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, tappable to toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .symbolEffect(.breathe, isActive: !isExpanded)

                    Text("Reasoning")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)

                    // Animated dots when collapsed (mimics ThinkingIndicator style)
                    if !isExpanded {
                        CollapsedThinkingDots()
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.purple.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Expandable content — Markdown-rendered thinking text
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ThinkingMarkdownText(text: text)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.purple.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            if !hasInitialized {
                hasInitialized = true
                // Live (streaming) thinking starts expanded; completed thinking starts collapsed
                isExpanded = isLive
            }
        }
        .onChange(of: isLive) { _, newValue in
            // When streaming finishes, auto-collapse
            if !newValue && isExpanded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded = false
                }
            }
        }
    }
}

// MARK: - Collapsed Thinking Dots (animated indicator)

private struct CollapsedThinkingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.purple.opacity(0.6))
                    .frame(width: 4, height: 4)
                    .scaleEffect(animating ? 1.0 : 0.4)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
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
