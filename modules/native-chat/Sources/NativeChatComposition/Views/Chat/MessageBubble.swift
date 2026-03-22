import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
import ChatUIComponents
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
    var showsRecoveryIndicator = false
    var isLiveThinking = false
    var liveThinkingPresentationState: ThinkingPresentationState?
    var suppressesPersistedThinking = false

    // File preview handler
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?
    let renderKey: RenderKey
    @Environment(\.hapticsEnabled) var hapticsEnabled

    var hapticService: HapticService {
        .shared
    }

    init(
        message: Message,
        onRegenerate: (() -> Void)? = nil,
        liveContent: String? = nil,
        liveThinking: String? = nil,
        activeToolCalls: [ToolCallInfo] = [],
        liveCitations: [URLCitation] = [],
        liveFilePathAnnotations: [FilePathAnnotation] = [],
        showsRecoveryIndicator: Bool = false,
        isLiveThinking: Bool = false,
        liveThinkingPresentationState: ThinkingPresentationState? = nil,
        suppressesPersistedThinking: Bool = false,
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
        self.isLiveThinking = isLiveThinking
        self.liveThinkingPresentationState = liveThinkingPresentationState
        self.suppressesPersistedThinking = suppressesPersistedThinking
        self.onSandboxLinkTap = onSandboxLinkTap
        renderKey = RenderKey(
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
            showsRecoveryIndicator: showsRecoveryIndicator,
            isLiveThinking: isLiveThinking,
            liveThinkingPresentationState: liveThinkingPresentationState,
            suppressesPersistedThinking: suppressesPersistedThinking
        )
    }
}
