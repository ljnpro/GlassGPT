import SwiftUI

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    var onRegenerate: (() -> Void)?

    // Live assistant state overrides (passed from ChatView during streaming/recovery)
    var liveContent: String?
    var liveThinking: String?
    var activeToolCalls: [ToolCallInfo] = []
    var liveCitations: [URLCitation] = []
    var liveFilePathAnnotations: [FilePathAnnotation] = []
    var showsRecoveryIndicator: Bool = false

    // File preview handler
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?
    let renderKey: RenderKey

    init(
        message: Message,
        onRegenerate: (() -> Void)? = nil,
        liveContent: String? = nil,
        liveThinking: String? = nil,
        activeToolCalls: [ToolCallInfo] = [],
        liveCitations: [URLCitation] = [],
        liveFilePathAnnotations: [FilePathAnnotation] = [],
        showsRecoveryIndicator: Bool = false,
        onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)? = nil
    ) {
        self.message = message
        self.onRegenerate = onRegenerate
        self.liveContent = liveContent
        self.liveThinking = liveThinking
        self.activeToolCalls = activeToolCalls
        self.liveCitations = liveCitations
        self.liveFilePathAnnotations = liveFilePathAnnotations
        self.showsRecoveryIndicator = showsRecoveryIndicator
        self.onSandboxLinkTap = onSandboxLinkTap
        self.renderKey = RenderKey(
            messageID: message.id,
            roleRawValue: message.roleRawValue,
            content: message.content,
            thinking: message.thinking,
            imageData: message.imageData,
            responseId: message.responseId,
            lastSequenceNumber: message.lastSequenceNumber,
            isComplete: message.isComplete,
            payloadRenderDigest: message.payloadRenderDigest,
            liveContent: liveContent,
            liveThinking: liveThinking,
            activeToolCalls: activeToolCalls,
            liveCitations: liveCitations,
            liveFilePathAnnotations: liveFilePathAnnotations,
            showsRecoveryIndicator: showsRecoveryIndicator
        )
    }
}
