import ChatDomain

/// Derived presentation state for the detached streaming assistant bubble.
public struct DetachedStreamingBubbleContentState: Equatable, Sendable {
    public let hasActiveWebSearch: Bool
    public let hasActiveCodeInterpreter: Bool
    public let hasActiveFileSearch: Bool
    public let completedCodeCalls: [ToolCallInfo]
    public let showsThinkingIndicator: Bool
    public let showsTypingIndicator: Bool
    public let showsCitations: Bool

    /// Computes detached-bubble presentation flags from the current streaming tool and text state.
    public init(
        activeToolCalls: [ToolCallInfo],
        currentThinkingText: String,
        currentStreamingText: String,
        isThinking: Bool,
        liveCitations: [URLCitation]
    ) {
        hasActiveWebSearch = activeToolCalls.contains {
            $0.type == .webSearch && $0.status != .completed
        }
        hasActiveCodeInterpreter = activeToolCalls.contains {
            $0.type == .codeInterpreter && $0.status != .completed
        }
        hasActiveFileSearch = activeToolCalls.contains {
            $0.type == .fileSearch && $0.status != .completed
        }
        completedCodeCalls = activeToolCalls.filter {
            $0.type == .codeInterpreter && $0.status == .completed
        }
        showsThinkingIndicator = isThinking && currentThinkingText.isEmpty && currentStreamingText.isEmpty
        showsTypingIndicator = !isThinking
            && currentStreamingText.isEmpty
            && currentThinkingText.isEmpty
            && activeToolCalls.allSatisfy { $0.status == .completed }
        showsCitations = !liveCitations.isEmpty
    }
}
