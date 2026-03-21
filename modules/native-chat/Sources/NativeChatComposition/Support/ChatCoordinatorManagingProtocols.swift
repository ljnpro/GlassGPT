import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport

@MainActor
protocol ChatConversationManaging: AnyObject {
    func startNewChat()
    func saveContext(reportingUserError userError: String?, logContext: String) -> Bool
    func saveContextIfPossible(_ logContext: String)
    func loadDefaultsFromSettings()
    func loadConversation(_ conversation: Conversation)
    func restoreLastConversationIfAvailable()
    func activeIncompleteAssistantDraft() -> Message?
    func applyConversationConfiguration(from conversation: Conversation)
    func applyConversationConfiguration(_ configuration: ConversationConfiguration)
    func sessionRequestConfiguration(for conversation: Conversation?) -> (ModelType, ReasoningEffort, ServiceTier)
    func buildRequestMessages(for conversation: Conversation, excludingDraft draftID: UUID) -> [APIMessage]
    func findMessage(byId id: UUID) -> Message?
    func detachBackgroundResponseIfPossible(reason: String) -> Bool
    func visibleMessages(for conversation: Conversation) -> [Message]
    func syncConversationConfiguration()
    func upsertMessage(_ message: Message)
}

@MainActor
protocol ChatSessionManaging: AnyObject {
    var currentVisibleSession: ReplySession? { get }
    var visibleSessionMessageID: UUID? { get }
    func makeRecoverySession(for message: Message) -> ReplySession?
    func registerSession(
        _ session: ReplySession,
        execution: SessionExecutionState,
        visible: Bool,
        syncIfCurrentlyVisible: Bool
    )
    func isSessionActive(_ session: ReplySession) -> Bool
    func bindVisibleSession(messageID: UUID?)
    func detachVisibleSessionBinding()
    func syncVisibleState(from session: ReplySession)
    func refreshVisibleBindingForCurrentConversation()
    func applyRuntimeTransition(_ transition: ReplyRuntimeTransition, to session: ReplySession) async -> ReplyRuntimeState?
    func runtimeState(for session: ReplySession) async -> ReplyRuntimeState?
    func runtimeSession(for session: ReplySession) async -> ReplySessionActor?
    func cachedRuntimeState(for session: ReplySession) -> ReplyRuntimeState?
    func saveSessionIfNeeded(_ session: ReplySession)
    func saveSessionNow(_ session: ReplySession)
    func finalizeSession(_ session: ReplySession)
    func finalizeSessionAsPartial(_ session: ReplySession)
    func removeEmptyMessage(_ message: Message, for session: ReplySession)
    func removeSession(_ session: ReplySession)
    func clearLiveGenerationState(clearDraft: Bool)
    func suspendActiveSessionsForAppBackground()
    func runtimeRoute(for session: ReplySession) -> OpenAITransportRoute
}

@MainActor
protocol ChatStreamingRequestStarting: AnyObject {
    func startStreamingRequest(reconnectAttempt: Int)
    func startStreamingRequest(for session: ReplySession, reconnectAttempt: Int)
    func applyStreamEvent(_ event: StreamEvent, to session: ReplySession, animated: Bool) async -> ReplyStreamEventOutcome
}

@MainActor
protocol ChatRecoveryManaging: AnyObject {
    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool
    )

    func startStreamingRecovery(
        session: ReplySession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool
    ) async

    func pollResponseUntilTerminal(session: ReplySession, responseId: String) async
    func cancelBackgroundResponseAndSync(responseId: String, messageId: UUID) async
}

@MainActor
protocol ChatRecoveryMaintenanceManaging: AnyObject {
    func recoverIncompleteMessages() async
    func cleanupStaleDrafts() async
    func resendOrphanedDrafts() async
    func recoverIncompleteMessagesInCurrentConversation() async
    func recoverSingleMessage(message: Message, responseId: String, visible: Bool)
}

@MainActor
protocol ChatDraftPreparing: AnyObject {
    var apiKey: String { get }
    var hasAPIKey: Bool { get }
    func prepareExistingDraft(_ draft: Message) throws(SendMessagePreparationError) -> PreparedAssistantReply
    func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment]
}

@MainActor
protocol ChatFileInteractionManaging: AnyObject {
    func prefetchGeneratedFilesIfNeeded(for message: Message)
}

extension ChatConversationCoordinator: ChatConversationManaging {}
extension ChatSessionCoordinator: ChatSessionManaging {}
extension ChatStreamingCoordinator: ChatStreamingRequestStarting {}
extension ChatRecoveryCoordinator: ChatRecoveryManaging {}
extension ChatRecoveryMaintenanceCoordinator: ChatRecoveryMaintenanceManaging {}
extension ChatSendCoordinator: ChatDraftPreparing {}
extension ChatFileInteractionCoordinator: ChatFileInteractionManaging {}
