import Foundation

enum RecoveryPhase: Equatable {
    case idle
    case checkingStatus
    case streamResuming
    case pollingTerminal
}

@MainActor
final class ResponseSession {
    let messageID: UUID
    let conversationID: UUID
    let service: OpenAIService
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
        message: Message,
        conversationID: UUID,
        service: OpenAIService,
        requestMessages: [APIMessage]? = nil,
        requestModel: ModelType,
        requestEffort: ReasoningEffort,
        requestUsesBackgroundMode: Bool,
        requestServiceTier: ServiceTier
    ) {
        self.messageID = message.id
        self.conversationID = conversationID
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
