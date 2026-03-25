import ChatDomain
import ChatPresentation
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
    /// The current presentation state of any streamed reasoning text.
    let thinkingPresentationState: ThinkingPresentationState?
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
        thinkingPresentationState: ThinkingPresentationState?,
        liveCitations: [URLCitation],
        streamingThinkingExpanded: Binding<Bool?>,
        assistantBubbleMaxWidth: CGFloat
    ) {
        self.activeToolCalls = activeToolCalls
        self.currentThinkingText = currentThinkingText
        self.currentStreamingText = currentStreamingText
        self.isThinking = isThinking
        self.isStreaming = isStreaming
        self.thinkingPresentationState = thinkingPresentationState
        self.liveCitations = liveCitations
        _streamingThinkingExpanded = streamingThinkingExpanded
        self.assistantBubbleMaxWidth = assistantBubbleMaxWidth
        renderKey = RenderKey(
            activeToolCalls: activeToolCalls,
            currentThinkingText: currentThinkingText,
            currentStreamingText: currentStreamingText,
            isThinking: isThinking,
            isStreaming: isStreaming,
            thinkingPresentationState: thinkingPresentationState,
            liveCitations: liveCitations,
            assistantBubbleMaxWidth: assistantBubbleMaxWidth
        )
    }

    package nonisolated static func == (lhs: DetachedStreamingBubbleView, rhs: DetachedStreamingBubbleView) -> Bool {
        lhs.renderKey == rhs.renderKey
    }

    /// The detached assistant bubble used while a response is still streaming.
    package var body: some View {
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

            if isThinking, currentThinkingText.isEmpty, currentStreamingText.isEmpty {
                ThinkingIndicator()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if !currentThinkingText.isEmpty {
                ThinkingView(
                    text: currentThinkingText,
                    phase: thinkingPresentationState ?? .completed,
                    externalIsExpanded: $streamingThinkingExpanded
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !currentStreamingText.isEmpty {
                StreamingTextView(
                    text: currentStreamingText,
                    allowsSelection: false
                )
            } else if !isThinking, currentThinkingText.isEmpty,
                      activeToolCalls.allSatisfy({ $0.status == .completed }) {
                TypingIndicator()
            }

            if !liveCitations.isEmpty {
                CitationLinksView(citations: liveCitations)
            }
        }
        .padding(12)
        .singleSurfaceGlass(
            cornerRadius: 20,
            stableFillOpacity: GlassStyleMetrics.AssistantSurface.liveStableFillOpacity,
            tintOpacity: GlassStyleMetrics.AssistantSurface.liveTintOpacity,
            borderWidth: GlassStyleMetrics.AssistantSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.AssistantSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.AssistantSurface.lightBorderOpacity
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Assistant response in progress"))
        .accessibilityIdentifier("chat.assistant.detachedSurface")
        .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension DetachedStreamingBubbleView {
    struct RenderKey: Equatable {
        let activeToolCalls: [ToolCallInfo]
        let currentThinkingText: String
        let currentStreamingText: String
        let isThinking: Bool
        let isStreaming: Bool
        let thinkingPresentationState: ThinkingPresentationState?
        let liveCitations: [URLCitation]
        let assistantBubbleMaxWidth: CGFloat
    }
}
