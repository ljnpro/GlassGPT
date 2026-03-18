import SwiftUI
import SwiftData
import UIKit
import ChatApplication
import ChatRuntimePorts
import ChatRuntimeWorkflows

@Observable
@MainActor
final class ChatScreenStore: ChatRuntimeScreenStore {

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
    let filePreviewStore = FilePreviewStore()

    // MARK: - Dependencies

    let dependencies: NativeChatFeatureDependencies

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
    lazy var runtimeRegistry = RuntimeRegistryActor()
    @ObservationIgnored
    lazy var sendPreparationPort = LegacySendMessagePreparationAdapter(store: self)
    @ObservationIgnored
    lazy var chatSceneController = ChatSceneController(
        registry: runtimeRegistry,
        preparationPort: sendPreparationPort
    )
    @ObservationIgnored
    lazy var conversationRuntime = ChatRuntimeEngine(
        viewModel: self,
        runtimeRegistry: runtimeRegistry,
        chatSceneController: chatSceneController,
        sendPreparationPort: sendPreparationPort
    )

    // MARK: - Init

    init(
        modelContext: ModelContext,
        settingsStore: SettingsStore = .shared,
        apiKeyStore: APIKeyStore = .shared,
        configurationProvider: OpenAIConfigurationProvider = DefaultOpenAIConfigurationProvider.shared,
        transport: OpenAIDataTransport = OpenAIURLSessionTransport(),
        serviceFactory: (@MainActor () -> OpenAIService)? = nil,
        bootstrapPolicy: ChatScreenStoreBootstrapPolicy = .live
    ) {
        let resolvedRequestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
        let resolvedResponseParser = OpenAIResponseParser()
        let resolvedServiceFactory = serviceFactory ?? {
            OpenAIService(
                requestBuilder: resolvedRequestBuilder,
                responseParser: resolvedResponseParser,
                streamClient: SSEEventStream(),
                transport: transport
            )
        }
        let resolvedOpenAIService = resolvedServiceFactory()

        self.dependencies = NativeChatFeatureDependencies(
            modelContext: modelContext,
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            configurationProvider: configurationProvider,
            requestBuilder: resolvedRequestBuilder,
            responseParser: resolvedResponseParser,
            transport: transport,
            openAIService: resolvedOpenAIService,
            serviceFactory: resolvedServiceFactory
        )
        self.didCompleteLaunchBootstrap = !bootstrapPolicy.runLaunchTasks
        loadDefaultsFromSettings()
        if bootstrapPolicy.restoreLastConversation {
            restoreLastConversationIfAvailable()
        }
        syncConversationProjection()

        if bootstrapPolicy.setupLifecycleObservers {
            setupLifecycleObservers()
        }

        if bootstrapPolicy.runLaunchTasks {
            Task { @MainActor in
                await recoverIncompleteMessagesInCurrentConversation()
                await recoverIncompleteMessages()
                await resendOrphanedDrafts()
                self.didCompleteLaunchBootstrap = true
                await generateTitlesForUntitledConversations()
            }
        }
    }
}
