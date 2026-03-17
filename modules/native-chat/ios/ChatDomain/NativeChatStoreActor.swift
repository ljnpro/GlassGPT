import Foundation

struct ChatVisibleProjection: Equatable, Sendable {
    var draftMessageID: UUID?
    var currentStreamingText: String
    var currentThinkingText: String
    var activeToolCalls: [ToolCallInfo]
    var liveCitations: [URLCitation]
    var liveFilePathAnnotations: [FilePathAnnotation]
    var lastSequenceNumber: Int?
    var activeRequestModel: ModelType?
    var activeRequestEffort: ReasoningEffort?
    var activeRequestUsesBackgroundMode: Bool
    var activeRequestServiceTier: ServiceTier
    var isStreaming: Bool
    var isRecovering: Bool
    var visibleRecoveryPhase: RecoveryPhase
    var isThinking: Bool

    static let empty = ChatVisibleProjection(
        draftMessageID: nil,
        currentStreamingText: "",
        currentThinkingText: "",
        activeToolCalls: [],
        liveCitations: [],
        liveFilePathAnnotations: [],
        lastSequenceNumber: nil,
        activeRequestModel: nil,
        activeRequestEffort: nil,
        activeRequestUsesBackgroundMode: false,
        activeRequestServiceTier: .standard,
        isStreaming: false,
        isRecovering: false,
        visibleRecoveryPhase: .idle,
        isThinking: false
    )

    init(state: ChatVisibleSessionState) {
        self.draftMessageID = state.draftMessage?.id
        self.currentStreamingText = state.currentStreamingText
        self.currentThinkingText = state.currentThinkingText
        self.activeToolCalls = state.activeToolCalls
        self.liveCitations = state.liveCitations
        self.liveFilePathAnnotations = state.liveFilePathAnnotations
        self.lastSequenceNumber = state.lastSequenceNumber
        self.activeRequestModel = state.activeRequestModel
        self.activeRequestEffort = state.activeRequestEffort
        self.activeRequestUsesBackgroundMode = state.activeRequestUsesBackgroundMode
        self.activeRequestServiceTier = state.activeRequestServiceTier
        self.isStreaming = state.isStreaming
        self.isRecovering = state.isRecovering
        self.visibleRecoveryPhase = state.visibleRecoveryPhase
        self.isThinking = state.isThinking
    }

    init(
        draftMessageID: UUID?,
        currentStreamingText: String,
        currentThinkingText: String,
        activeToolCalls: [ToolCallInfo],
        liveCitations: [URLCitation],
        liveFilePathAnnotations: [FilePathAnnotation],
        lastSequenceNumber: Int?,
        activeRequestModel: ModelType?,
        activeRequestEffort: ReasoningEffort?,
        activeRequestUsesBackgroundMode: Bool,
        activeRequestServiceTier: ServiceTier,
        isStreaming: Bool,
        isRecovering: Bool,
        visibleRecoveryPhase: RecoveryPhase,
        isThinking: Bool
    ) {
        self.draftMessageID = draftMessageID
        self.currentStreamingText = currentStreamingText
        self.currentThinkingText = currentThinkingText
        self.activeToolCalls = activeToolCalls
        self.liveCitations = liveCitations
        self.liveFilePathAnnotations = liveFilePathAnnotations
        self.lastSequenceNumber = lastSequenceNumber
        self.activeRequestModel = activeRequestModel
        self.activeRequestEffort = activeRequestEffort
        self.activeRequestUsesBackgroundMode = activeRequestUsesBackgroundMode
        self.activeRequestServiceTier = activeRequestServiceTier
        self.isStreaming = isStreaming
        self.isRecovering = isRecovering
        self.visibleRecoveryPhase = visibleRecoveryPhase
        self.isThinking = isThinking
    }
}

enum ChatAction: Sendable {
    case setConversation(UUID?)
    case applyVisibleProjection(visibleMessageID: UUID?, projection: ChatVisibleProjection)
    case clearVisibleProjection(retainedDraftMessageID: UUID?, clearDraft: Bool)
}

enum ChatEffect: Sendable {
    case none
}

actor NativeChatStoreActor {
    private(set) var currentConversationID: UUID?
    private(set) var visibleMessageID: UUID?
    private(set) var visibleProjection: ChatVisibleProjection = .empty

    @discardableResult
    func send(_ action: ChatAction) -> ChatEffect {
        switch action {
        case .setConversation(let conversationID):
            currentConversationID = conversationID

        case .applyVisibleProjection(let visibleMessageID, let projection):
            self.visibleMessageID = visibleMessageID
            visibleProjection = projection

        case .clearVisibleProjection(let retainedDraftMessageID, let clearDraft):
            visibleProjection = .empty
            visibleProjection.draftMessageID = clearDraft ? nil : retainedDraftMessageID
            if clearDraft {
                visibleMessageID = nil
            }
        }

        return .none
    }
}
