import Foundation

@MainActor
protocol ChatRuntimeScreenStore: AnyObject {
    var apiKey: String { get }
    var currentConversation: Conversation? { get set }
    var currentStreamingText: String { get }
    var currentThinkingText: String { get }
    var isStreaming: Bool { get }
    var selectedModel: ModelType { get }
    var reasoningEffort: ReasoningEffort { get }
    var backgroundModeEnabled: Bool { get }
    var serviceTier: ServiceTier { get }
    var selectedImageData: Data? { get set }
    var pendingAttachments: [FileAttachment] { get set }
    var draftMessage: Message? { get set }
    var errorMessage: String? { get set }
    var messages: [Message] { get set }
    var currentVisibleSession: ResponseSession? { get }
    var visibleSessionMessageID: UUID? { get }
    var conversationConfiguration: ConversationConfiguration { get }
    var openAIService: OpenAIService { get }
    var conversationRepository: ConversationRepository { get }
    var messagePersistence: MessagePersistenceAdapter { get }
    var serviceFactory: @MainActor () -> OpenAIService { get }
    var sessionRegistry: ChatSessionRegistry { get }

    func sessionRequestConfiguration(for conversation: Conversation?) -> (ModelType, ReasoningEffort, ServiceTier)
    func buildRequestMessages(for conversation: Conversation, excludingDraft draftID: UUID) -> [APIMessage]
    func makeStreamingSession(for draft: Message) -> ResponseSession?
    func makeRecoverySession(for message: Message) -> ResponseSession?
    func registerSession(_ session: ResponseSession, visible: Bool)
    func isSessionActive(_ session: ResponseSession) -> Bool
    func bindVisibleSession(messageID: UUID?)
    func setVisibleRecoveryPhase(_ phase: RecoveryPhase)
    func setRecoveryPhase(_ phase: RecoveryPhase, for session: ResponseSession)
    func syncVisibleState(from session: ResponseSession)
    func saveSessionIfNeeded(_ session: ResponseSession)
    func saveSessionNow(_ session: ResponseSession)
    func finalizeSession(_ session: ResponseSession)
    func finalizeSessionAsPartial(_ session: ResponseSession)
    func removeEmptyMessage(_ message: Message, for session: ResponseSession)
    func removeSession(_ session: ResponseSession)
    func clearLiveGenerationState(clearDraft: Bool)
    func applyVisibleState(_ state: ChatVisibleSessionState)
    func upsertMessage(_ message: Message)
    func saveContext(reportingUserError userError: String?, logContext: String) -> Bool
    func saveContextIfPossible(_ logContext: String)
    func findMessage(byId id: UUID) -> Message?
    func prefetchGeneratedFilesIfNeeded(for message: Message)
    func generateTitleIfNeeded(for conversation: Conversation) async
    func applyStreamEvent(_ event: StreamEvent, to session: ResponseSession, animated: Bool) -> StreamEventDisposition
    func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment]
    func endBackgroundTask()
    func interruptedResponseFallbackText(for message: Message, session: ResponseSession?) -> String
}
