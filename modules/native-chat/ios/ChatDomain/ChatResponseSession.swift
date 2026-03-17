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
    let service = OpenAIService()
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
    var lastSequenceNumber: Int?
    var responseId: String?

    var isStreaming = false
    var recoveryPhase: RecoveryPhase = .idle
    var isThinking = false
    var activeStreamID = UUID()
    var lastDraftSaveTime: Date = .distantPast
    var task: Task<Void, Never>?

    init(
        message: Message,
        conversationID: UUID,
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
        self.currentText = message.content
        self.currentThinking = message.thinking ?? ""
        self.toolCalls = message.toolCalls
        self.citations = message.annotations
        self.filePathAnnotations = message.filePathAnnotations
        self.lastSequenceNumber = message.lastSequenceNumber
        self.responseId = message.responseId
    }
}
