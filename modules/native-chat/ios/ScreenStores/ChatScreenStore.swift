import SwiftUI
import SwiftData
import UIKit

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - State

    var messages: [Message] = []
    var currentStreamingText: String = ""
    var currentThinkingText: String = ""
    var isStreaming: Bool = false
    var isThinking: Bool = false
    var isRecovering: Bool = false
    var isRestoringConversation: Bool = false
    var selectedModel: ModelType = .gpt5_4 {
        didSet {
            if !selectedModel.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = selectedModel.defaultEffort
            }
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            syncConversationConfiguration()
        }
    }
    var reasoningEffort: ReasoningEffort = .high {
        didSet {
            guard selectedModel.availableEfforts.contains(reasoningEffort) else {
                reasoningEffort = selectedModel.defaultEffort
                return
            }
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            syncConversationConfiguration()
        }
    }
    var backgroundModeEnabled: Bool = false {
        didSet {
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            syncConversationConfiguration()
        }
    }
    var serviceTier: ServiceTier = .standard {
        didSet {
            guard !isApplyingStoredConversationConfiguration && !isApplyingConversationConfigurationBatch else { return }
            syncConversationConfiguration()
        }
    }
    var currentConversation: Conversation?
    var errorMessage: String?
    var selectedImageData: Data?

    // Tool call state
    var activeToolCalls: [ToolCallInfo] = []
    var liveCitations: [URLCitation] = []
    var liveFilePathAnnotations: [FilePathAnnotation] = []

    // File attachments pending send
    var pendingAttachments: [FileAttachment] = []

    // File preview state
    var filePreviewItem: FilePreviewItem?
    var sharedGeneratedFileItem: SharedGeneratedFileItem?
    var isDownloadingFile: Bool = false
    var fileDownloadError: String?

    // MARK: - Dependencies

    let configurationProvider: OpenAIConfigurationProvider
    let requestBuilder: OpenAIRequestBuilder
    let responseParser: OpenAIResponseParser
    let transport: OpenAIDataTransport
    let openAIService: OpenAIService
    let settingsStore: SettingsStore
    let apiKeyStore: APIKeyStore
    let conversationRepository: ConversationRepository
    let draftRepository: DraftRepository
    let generatedFileCoordinator = GeneratedFileCoordinator()
    let messagePersistence = MessagePersistenceAdapter()
    let backgroundTaskCoordinator = BackgroundTaskCoordinator()
    let serviceFactory: () -> OpenAIService
    var modelContext: ModelContext

    // Visible live session state
    var draftMessage: Message?
    var lastSequenceNumber: Int?
    var activeRequestModel: ModelType?
    var activeRequestEffort: ReasoningEffort?
    var activeRequestUsesBackgroundMode = false
    var activeRequestServiceTier: ServiceTier = .standard
    var isApplyingStoredConversationConfiguration = false
    var isApplyingConversationConfigurationBatch = false
    var didCompleteLaunchBootstrap = false
    var visibleRecoveryPhase: RecoveryPhase = .idle
    @ObservationIgnored
    lazy var conversationRuntime = ConversationRuntime(viewModel: self)

    var sessionRegistry: ChatSessionRegistry {
        conversationRuntime.sessionStateStore.registry
    }

    // MARK: - Init

    init(
        modelContext: ModelContext,
        settingsStore: SettingsStore = .shared,
        apiKeyStore: APIKeyStore = .shared,
        configurationProvider: OpenAIConfigurationProvider = DefaultOpenAIConfigurationProvider.shared,
        transport: OpenAIDataTransport = OpenAIURLSessionTransport()
    ) {
        let resolvedRequestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
        let resolvedResponseParser = OpenAIResponseParser()
        let resolvedServiceFactory = {
            OpenAIService(
                requestBuilder: resolvedRequestBuilder,
                responseParser: resolvedResponseParser,
                streamClient: SSEEventStream(),
                transport: transport
            )
        }

        self.modelContext = modelContext
        self.configurationProvider = configurationProvider
        self.requestBuilder = resolvedRequestBuilder
        self.responseParser = resolvedResponseParser
        self.transport = transport
        self.openAIService = resolvedServiceFactory()
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.conversationRepository = ConversationRepository(modelContext: modelContext)
        self.draftRepository = DraftRepository(modelContext: modelContext)
        self.serviceFactory = resolvedServiceFactory
        loadDefaultsFromSettings()
        restoreLastConversationIfAvailable()

        setupLifecycleObservers()

        Task { @MainActor in
            await recoverIncompleteMessagesInCurrentConversation()
            await recoverIncompleteMessages()
            await resendOrphanedDrafts()
            self.didCompleteLaunchBootstrap = true
            await generateTitlesForUntitledConversations()
        }
    }

    var proModeEnabled: Bool {
        get { selectedModel == .gpt5_4_pro }
        set { selectedModel = newValue ? .gpt5_4_pro : .gpt5_4 }
    }

    var currentVisibleSession: ResponseSession? {
        sessionRegistry.currentVisibleSession
    }

    var visibleSessionMessageID: UUID? {
        get { sessionRegistry.visibleMessageID }
        set { sessionRegistry.bindVisibleSession(messageID: newValue) }
    }

    var liveDraftMessageID: UUID? {
        SessionVisibilityCoordinator.liveDraftMessageID(
            visibleMessageID: visibleSessionMessageID,
            messages: messages
        )
    }

    var shouldShowDetachedStreamingBubble: Bool {
        SessionVisibilityCoordinator.shouldShowDetachedStreamingBubble(
            isStreaming: isStreaming,
            liveDraftMessageID: liveDraftMessageID
        )
    }

    var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set { serviceTier = newValue ? .flex : .standard }
    }

    var conversationConfiguration: ConversationConfiguration {
        ConversationConfiguration(
            model: selectedModel,
            reasoningEffort: reasoningEffort,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTier: serviceTier
        )
    }

    func applyConversationConfiguration(_ configuration: ConversationConfiguration) {
        isApplyingConversationConfigurationBatch = true
        defer { isApplyingConversationConfigurationBatch = false }

        selectedModel = configuration.model
        reasoningEffort = configuration.reasoningEffort
        backgroundModeEnabled = configuration.backgroundModeEnabled
        serviceTier = configuration.serviceTier

        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
        }

        syncConversationConfiguration()
    }
}
