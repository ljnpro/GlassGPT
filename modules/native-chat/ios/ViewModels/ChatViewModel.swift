import SwiftUI
import SwiftData
import UIKit

enum FilePreviewKind: String, Sendable {
    case generatedImage
    case generatedPDF
}

struct FilePreviewItem: Identifiable, Sendable {
    let url: URL
    let kind: FilePreviewKind
    let displayName: String
    let viewerFilename: String

    var id: String { "\(kind.rawValue):\(url.path)" }
}

struct SharedGeneratedFileItem: Identifiable, Sendable {
    let url: URL
    let filename: String

    var id: String { url.path }
}

@Observable
@MainActor
final class ChatViewModel {

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

    let openAIService = OpenAIService()
    let settingsStore: SettingsStore
    let apiKeyStore: APIKeyStore
    let conversationRepository: ConversationRepository
    let draftRepository: DraftRepository
    let generatedFileCoordinator = GeneratedFileCoordinator()
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
    var visibleSessionMessageID: UUID?
    var visibleRecoveryPhase: RecoveryPhase = .idle
    var activeResponseSessions: [UUID: ResponseSession] = [:]

    // Background task
    var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Init

    init(
        modelContext: ModelContext,
        settingsStore: SettingsStore = .shared,
        apiKeyStore: APIKeyStore = .shared
    ) {
        self.modelContext = modelContext
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.conversationRepository = ConversationRepository(modelContext: modelContext)
        self.draftRepository = DraftRepository(modelContext: modelContext)
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
        guard let visibleSessionMessageID else { return nil }
        return activeResponseSessions[visibleSessionMessageID]
    }

    var liveDraftMessageID: UUID? {
        guard let visibleSessionMessageID,
              messages.contains(where: { $0.id == visibleSessionMessageID })
        else {
            return nil
        }

        return visibleSessionMessageID
    }

    var shouldShowDetachedStreamingBubble: Bool {
        isStreaming && liveDraftMessageID == nil
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
