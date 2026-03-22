import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import ChatRuntimeModel
import ChatRuntimeWorkflows
import ChatUIComponents
import Foundation
import GeneratedFilesCore
import GeneratedFilesInfra
import OpenAITransport
import SwiftData

@MainActor
protocol ChatConversationSelectionAccess: AnyObject {
    var currentConversation: Conversation? { get set }
}

@MainActor
protocol ChatMessageListAccess: AnyObject {
    var messages: [Message] { get set }
    var draftMessage: Message? { get set }
}

@MainActor
protocol ChatStreamingProjectionAccess: AnyObject {
    var currentStreamingText: String { get set }
    var currentThinkingText: String { get set }
    var isStreaming: Bool { get set }
    var isThinking: Bool { get set }
    var isRecovering: Bool { get set }
    var thinkingPresentationState: ThinkingPresentationState? { get set }
    var activeToolCalls: [ToolCallInfo] { get set }
    var liveCitations: [URLCitation] { get set }
    var liveFilePathAnnotations: [FilePathAnnotation] { get set }
    var lastSequenceNumber: Int? { get set }
    var activeRequestModel: ModelType? { get set }
    var activeRequestEffort: ReasoningEffort? { get set }
    var activeRequestUsesBackgroundMode: Bool { get set }
    var activeRequestServiceTier: ServiceTier { get set }
}

@MainActor
protocol ChatReplyFeedbackAccess: AnyObject {
    var errorMessage: String? { get set }
    var hapticsEnabled: Bool { get }
    var hapticService: HapticService { get }
}

@MainActor
protocol ChatAttachmentStateAccess: AnyObject {
    var selectedImageData: Data? { get set }
    var pendingAttachments: [FileAttachment] { get set }
}

@MainActor
protocol ChatConfigurationSelectionAccess: AnyObject {
    var selectedModel: ModelType { get set }
    var reasoningEffort: ReasoningEffort { get set }
    var backgroundModeEnabled: Bool { get set }
    var serviceTier: ServiceTier { get set }
    var isApplyingStoredConversationConfiguration: Bool { get set }
    var isApplyingConversationConfigurationBatch: Bool { get set }
    var conversationConfiguration: ConversationConfiguration { get }
    func syncConversationProjection()
}

@MainActor
protocol ChatPreviewStateAccess: AnyObject {
    var filePreviewItem: FilePreviewItem? { get set }
    var sharedGeneratedFileItem: SharedGeneratedFileItem? { get set }
    var isDownloadingFile: Bool { get set }
    var fileDownloadError: String? { get set }
}

@MainActor
protocol ChatBootstrapStateAccess: AnyObject {
    var didCompleteLaunchBootstrap: Bool { get set }
}

@MainActor
protocol ChatPersistenceAccess: AnyObject {
    var modelContext: ModelContext { get }
    var settingsStore: SettingsStore { get }
    var conversationRepository: ConversationRepository { get }
    var draftRepository: DraftRepository { get }
    var messagePersistence: MessagePersistenceAdapter { get }
}

@MainActor
protocol ChatTransportServiceAccess: AnyObject {
    var apiKeyStore: PersistedAPIKeyStore { get }
    var configurationProvider: OpenAIConfigurationProvider { get }
    var requestBuilder: OpenAIRequestBuilder { get }
    var responseParser: OpenAIResponseParser { get }
    var transport: OpenAIDataTransport { get }
    var openAIService: OpenAIService { get }
    var serviceFactory: @MainActor () -> OpenAIService { get }
}

@MainActor
protocol ChatGeneratedFileServiceAccess: AnyObject {
    var generatedFileCoordinator: GeneratedFileCoordinator { get }
    var fileDownloadService: FileDownloadService { get }
    var generatedFilePrefetchRegistry: GeneratedFilePrefetchRegistry { get }
    func cancelGeneratedFilePrefetches(_ requests: Set<GeneratedFilePrefetchRequest>)
}

@MainActor
protocol ChatBackgroundTaskAccess: AnyObject {
    var backgroundTaskCoordinator: BackgroundTaskCoordinator { get }
    func endBackgroundTask()
}

@MainActor
protocol ChatRuntimeRegistryAccess: AnyObject {
    var sessionRegistry: ChatSessionRegistry { get }
    var runtimeRegistry: RuntimeRegistryActor { get }
}

typealias ChatSessionCoordinatorStateAccess =
    ChatConversationSelectionAccess &
    ChatMessageListAccess &
    ChatReplyFeedbackAccess &
    ChatStreamingProjectionAccess

typealias ChatSessionCoordinatorServiceAccess =
    ChatBackgroundTaskAccess &
    ChatGeneratedFileServiceAccess &
    ChatPersistenceAccess &
    ChatRuntimeRegistryAccess &
    ChatTransportServiceAccess

extension ChatController:
    ChatConversationSelectionAccess,
    ChatMessageListAccess,
    ChatStreamingProjectionAccess,
    ChatReplyFeedbackAccess,
    ChatAttachmentStateAccess,
    ChatConfigurationSelectionAccess,
    ChatPreviewStateAccess,
    ChatBootstrapStateAccess,
    ChatPersistenceAccess,
    ChatTransportServiceAccess,
    ChatGeneratedFileServiceAccess,
    ChatBackgroundTaskAccess,
    ChatRuntimeRegistryAccess {}
