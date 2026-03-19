import ChatDomain
import ChatUIComponents
import SwiftUI

/// Displays the live assistant response bubble during streaming, including tool-call indicators,
/// thinking text, streaming text, and citation links.
package struct DetachedStreamingBubbleView: View, Equatable {
    /// Active tool calls being executed by the model.
    let activeToolCalls: [ToolCallInfo]
    /// The current reasoning/thinking text emitted by the model.
    let currentThinkingText: String
    /// The current response text being streamed.
    let currentStreamingText: String
    /// Whether the model is actively reasoning.
    let isThinking: Bool
    /// Whether content is actively being streamed.
    let isStreaming: Bool
    /// Citations collected during web search tool calls.
    let liveCitations: [URLCitation]
    /// External binding controlling the thinking disclosure expanded state.
    @Binding var streamingThinkingExpanded: Bool?
    /// Maximum width for the assistant bubble.
    let assistantBubbleMaxWidth: CGFloat
    private let renderKey: RenderKey

    /// Creates a detached streaming bubble with the given streaming state.
    package init(
        activeToolCalls: [ToolCallInfo],
        currentThinkingText: String,
        currentStreamingText: String,
        isThinking: Bool,
        isStreaming: Bool,
        liveCitations: [URLCitation],
        streamingThinkingExpanded: Binding<Bool?>,
        assistantBubbleMaxWidth: CGFloat
    ) {
        self.activeToolCalls = activeToolCalls
        self.currentThinkingText = currentThinkingText
        self.currentStreamingText = currentStreamingText
        self.isThinking = isThinking
        self.isStreaming = isStreaming
        self.liveCitations = liveCitations
        self._streamingThinkingExpanded = streamingThinkingExpanded
        self.assistantBubbleMaxWidth = assistantBubbleMaxWidth
        self.renderKey = RenderKey(
            activeToolCalls: activeToolCalls,
            currentThinkingText: currentThinkingText,
            currentStreamingText: currentStreamingText,
            isThinking: isThinking,
            isStreaming: isStreaming,
            liveCitations: liveCitations,
            assistantBubbleMaxWidth: assistantBubbleMaxWidth
        )
    }

    nonisolated package static func == (lhs: DetachedStreamingBubbleView, rhs: DetachedStreamingBubbleView) -> Bool {
        lhs.renderKey == rhs.renderKey
    }

    package var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                let hasActiveWebSearch = activeToolCalls.contains {
                    $0.type == .webSearch && $0.status != .completed
                }
                if hasActiveWebSearch {
                    WebSearchIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                let hasActiveCodeInterpreter = activeToolCalls.contains {
                    $0.type == .codeInterpreter && $0.status != .completed
                }
                if hasActiveCodeInterpreter {
                    CodeInterpreterIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                let hasActiveFileSearch = activeToolCalls.contains {
                    $0.type == .fileSearch && $0.status != .completed
                }
                if hasActiveFileSearch {
                    FileSearchIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                let completedCodeCalls = activeToolCalls.filter {
                    $0.type == .codeInterpreter && $0.status == .completed
                }
                ForEach(completedCodeCalls) { toolCall in
                    CodeInterpreterResultView(toolCall: toolCall)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isThinking {
                    ThinkingIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                if !currentThinkingText.isEmpty {
                    ThinkingView(
                        text: currentThinkingText,
                        isLive: isThinking || isStreaming,
                        externalIsExpanded: $streamingThinkingExpanded
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !currentStreamingText.isEmpty {
                    StreamingTextView(
                        text: currentStreamingText,
                        allowsSelection: false
                    )
                } else if !isThinking && currentThinkingText.isEmpty
                            && activeToolCalls.allSatisfy({ $0.status == .completed }) {
                    TypingIndicator()
                }

                if !liveCitations.isEmpty {
                    CitationLinksView(citations: liveCitations)
                }
            }
            .padding(12)
            .singleSurfaceGlass(
                cornerRadius: 20,
                stableFillOpacity: 0.01,
                tintOpacity: 0.03,
                borderWidth: 0.85,
                darkBorderOpacity: 0.16,
                lightBorderOpacity: 0.09
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Assistant response in progress")
            .accessibilityIdentifier("chat.assistant.detachedSurface")
            .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)

            Spacer(minLength: 40)
        }
    }
}

private extension DetachedStreamingBubbleView {
    struct RenderKey: Equatable {
        let activeToolCalls: [ToolCallInfo]
        let currentThinkingText: String
        let currentStreamingText: String
        let isThinking: Bool
        let isStreaming: Bool
        let liveCitations: [URLCitation]
        let assistantBubbleMaxWidth: CGFloat
    }
}
