import Foundation
import ChatDomain
import ChatRuntimeModel

enum RecoveryPhase: Equatable {
    case idle
    case checkingStatus
    case streamResuming
    case pollingTerminal
}

@MainActor
final class ResponseSession {
    let assistantReplyID: AssistantReplyID
    let messageID: UUID
    let conversationID: UUID
    let service: OpenAIService
    let requestAPIKey: String
    let requestMessages: [APIMessage]?
    let requestModel: ModelType
    let requestEffort: ReasoningEffort
    let requestUsesBackgroundMode: Bool
    let requestServiceTier: ServiceTier

    var currentText: String
    var currentThinking: String
    var toolCalls: [ToolCallInfo]
    var citations: [URLCitation]
    var filePathAnnotations: [FilePathAnnotation]
    private(set) var runtimeState: ChatRuntimeState
    var lastDraftSaveTime: Date = .distantPast
    var task: Task<Void, Never>?

    init(
        assistantReplyID: AssistantReplyID? = nil,
        message: Message,
        conversationID: UUID,
        service: OpenAIService,
        requestAPIKey: String = "",
        requestMessages: [APIMessage]? = nil,
        requestModel: ModelType,
        requestEffort: ReasoningEffort,
        requestUsesBackgroundMode: Bool,
        requestServiceTier: ServiceTier
    ) {
        self.assistantReplyID = assistantReplyID ?? AssistantReplyID(rawValue: message.id)
        self.messageID = message.id
        self.conversationID = conversationID
        self.requestAPIKey = requestAPIKey
        self.requestMessages = requestMessages
        self.requestModel = requestModel
        self.requestEffort = requestEffort
        self.requestUsesBackgroundMode = requestUsesBackgroundMode
        self.requestServiceTier = requestServiceTier
        self.service = service
        self.currentText = message.content
        self.currentThinking = message.thinking ?? ""
        self.toolCalls = message.toolCalls
        self.citations = message.annotations
        self.filePathAnnotations = message.filePathAnnotations
        self.runtimeState = ChatRuntimeState(
            responseId: message.responseId,
            lastSequenceNumber: message.lastSequenceNumber,
            backgroundResumable: message.usedBackgroundMode
        )
    }

    convenience init(
        preparedReply: PreparedAssistantReply,
        service: OpenAIService
    ) {
        let message = Message(
            id: preparedReply.draftMessageID,
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: preparedReply.requestUsesBackgroundMode,
            isComplete: false
        )
        self.init(
            assistantReplyID: preparedReply.assistantReplyID,
            message: message,
            conversationID: preparedReply.conversationID,
            service: service,
            requestAPIKey: preparedReply.apiKey,
            requestMessages: preparedReply.requestMessages,
            requestModel: preparedReply.requestModel,
            requestEffort: preparedReply.requestEffort,
            requestUsesBackgroundMode: preparedReply.requestUsesBackgroundMode,
            requestServiceTier: preparedReply.requestServiceTier
        )
    }

    var lastSequenceNumber: Int? {
        get { runtimeState.lastSequenceNumber }
        set { runtimeState.lastSequenceNumber = newValue }
    }

    var responseId: String? {
        get { runtimeState.responseId }
        set { runtimeState.responseId = newValue }
    }

    var isStreaming: Bool {
        runtimeState.isStreaming
    }

    var recoveryPhase: RecoveryPhase {
        runtimeState.recoveryPhase
    }

    var isThinking: Bool {
        get { runtimeState.isThinking }
        set { runtimeState.isThinking = newValue }
    }

    var activeStreamID: UUID {
        get { runtimeState.activeStreamID }
        set { runtimeState.activeStreamID = newValue }
    }

    var phase: ChatRuntimeEnginePhase {
        runtimeState.phase
    }

    func beginSubmitting() {
        runtimeState.phase = .submitting
        runtimeState.recoveryPhase = .idle
        runtimeState.isThinking = false
    }

    func beginStreaming(streamID: UUID) {
        runtimeState.phase = .streaming
        runtimeState.recoveryPhase = .idle
        runtimeState.activeStreamID = streamID
        runtimeState.isThinking = false
    }

    func beginRecoveryCheck(responseId: String) {
        runtimeState.responseId = responseId
        runtimeState.phase = .recoveringStatus
        runtimeState.recoveryPhase = .checkingStatus
        runtimeState.isThinking = false
    }

    func beginRecoveryStream(streamID: UUID) {
        runtimeState.phase = .recoveringStream
        runtimeState.recoveryPhase = .streamResuming
        runtimeState.activeStreamID = streamID
        runtimeState.isThinking = false
    }

    func beginRecoveryPoll() {
        runtimeState.phase = .recoveringPoll
        runtimeState.recoveryPhase = .pollingTerminal
        runtimeState.isThinking = false
    }

    func setRecoveryPhase(_ phase: RecoveryPhase) {
        runtimeState.recoveryPhase = phase
        switch phase {
        case .idle:
            if runtimeState.phase == .recoveringStatus || runtimeState.phase == .recoveringStream || runtimeState.phase == .recoveringPoll {
                runtimeState.phase = .idle
            }
        case .checkingStatus:
            runtimeState.phase = .recoveringStatus
        case .streamResuming:
            runtimeState.phase = .recoveringStream
        case .pollingTerminal:
            runtimeState.phase = .recoveringPoll
        }
    }

    func cancelStreaming() {
        runtimeState.activeStreamID = UUID()
        runtimeState.phase = .idle
        runtimeState.recoveryPhase = .idle
        runtimeState.isThinking = false
    }

    func beginFinalizing() {
        runtimeState.phase = .finalizing
    }

    func markCompleted() {
        runtimeState.phase = .completed
        runtimeState.recoveryPhase = .idle
        runtimeState.isThinking = false
        runtimeState.lastSequenceNumber = nil
    }

    func markFailed() {
        runtimeState.phase = .failed
        runtimeState.isThinking = false
    }
}
