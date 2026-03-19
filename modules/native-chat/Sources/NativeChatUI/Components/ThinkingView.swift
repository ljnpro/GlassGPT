import ChatUIComponents
import SwiftUI

// MARK: - Thinking Indicator (capsule shown while model is actively reasoning, before text arrives)

/// Animated capsule indicator shown while the model is actively reasoning, before thinking text arrives.
package struct ThinkingIndicator: View {
    /// Creates a new thinking indicator.
    package init() {}

    package var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)

            Text("Reasoning…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .singleSurfaceGlass(
            cornerRadius: 999,
            stableFillOpacity: 0.01,
            borderWidth: 0.75,
            darkBorderOpacity: 0.14,
            lightBorderOpacity: 0.08
        )
        .accessibilityLabel(String(localized: "Reasoning in progress"))
        .accessibilityIdentifier("indicator.thinking")
    }
}

// MARK: - Thinking View (card-style, collapsible reasoning text with Markdown rendering)

/// Collapsible card that displays the model's reasoning text with Markdown rendering.
package struct ThinkingView: View {
    /// The reasoning text emitted by the model.
    let text: String
    /// Whether the thinking is still in progress (streaming). When true, starts expanded.
    var isLive: Bool = false
    /// Optional external binding for expanded state (used during streaming to preserve state across re-renders)
    @Binding var externalIsExpanded: Bool?

    @State private var internalIsExpanded: Bool = false
    @State private var hasInitialized: Bool = false

    /// Use external binding if provided, otherwise fall back to internal state
    private var isExpanded: Bool {
        externalIsExpanded ?? internalIsExpanded
    }

    private func setExpanded(_ value: Bool) {
        if externalIsExpanded != nil {
            externalIsExpanded = value
        } else {
            internalIsExpanded = value
        }
    }

    /// Creates a thinking view with the given text and optional external expanded-state binding.
    package init(text: String, isLive: Bool = false, externalIsExpanded: Binding<Bool?> = .constant(nil)) {
        self.text = text
        self.isLive = isLive
        self._externalIsExpanded = externalIsExpanded
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap entire row to toggle expand/collapse
            HStack(spacing: 8) {
                Image(systemName: isLive ? "brain" : "brain.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, options: .repeating, isActive: isLive)
                    .accessibilityHidden(true)

                Text(isLive ? "Reasoning…" : "Reasoning Completed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .accessibilityLabel(isLive ? String(localized: "Reasoning in progress") : String(localized: "Reasoning completed"))
            .accessibilityHint(isExpanded ? "Double-tap to collapse" : "Double-tap to expand")
            .accessibilityIdentifier("thinking.header")
            .accessibilityAddTraits(.isButton)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    setExpanded(!isExpanded)
                }
            }

            // Expandable content — Markdown-rendered thinking text
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ThinkingMarkdownText(
                        text: text,
                        allowsSelection: !isLive
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .modifier(
            ThinkingSurfaceModifier(isLive: isLive)
        )
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

private struct ThinkingSurfaceModifier: ViewModifier {
    let isLive: Bool

    func body(content: Content) -> some View {
        content
            .singleSurfaceGlass(
                cornerRadius: 12,
                stableFillOpacity: isLive ? 0.012 : 0.004,
                tintOpacity: isLive ? 0.03 : 0.022,
                borderWidth: 0.8,
                darkBorderOpacity: 0.15,
                lightBorderOpacity: 0.085
            )
    }
}

// MARK: - Thinking Markdown Text (renders bold, italic, code, etc.)

private struct ThinkingMarkdownText: View {
    let text: String
    var allowsSelection: Bool = true

    var body: some View {
        let attributed = RichTextAttributedStringBuilder.parseThinkingText(text)
        Text(attributed)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .applyingIf(allowsSelection) { view in
                view.textSelection(.enabled)
            }
    }
}

// MARK: - Typing Indicator

/// Animated three-dot typing indicator shown while awaiting the first token.
package struct TypingIndicator: View {
    @State private var animating = false

    package init() {}

    package var body: some View {
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
        .accessibilityLabel(String(localized: "Waiting for response"))
        .accessibilityIdentifier("indicator.typing")
        .onAppear { animating = true }
    }
}
