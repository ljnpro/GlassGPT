import Foundation

extension ChatScreenStore {
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

    var filePreviewItem: FilePreviewItem? {
        get { filePreviewStore.filePreviewItem }
        set { filePreviewStore.filePreviewItem = newValue }
    }

    var sharedGeneratedFileItem: SharedGeneratedFileItem? {
        get { filePreviewStore.sharedGeneratedFileItem }
        set { filePreviewStore.sharedGeneratedFileItem = newValue }
    }

    var isDownloadingFile: Bool {
        get { filePreviewStore.isDownloadingFile }
        set { filePreviewStore.isDownloadingFile = newValue }
    }

    var fileDownloadError: String? {
        get { filePreviewStore.fileDownloadError }
        set { filePreviewStore.fileDownloadError = newValue }
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
