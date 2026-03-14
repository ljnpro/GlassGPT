import SwiftUI
import SwiftData
import UIKit

@Observable
@MainActor
final class ChatViewModel {

    private enum StorageKeys {
        static let defaultModel = "defaultModel"
        static let defaultEffort = "defaultEffort"
        static let defaultBackgroundModeEnabled = "defaultBackgroundModeEnabled"
        static let defaultServiceTier = "defaultServiceTier"
    }

    // MARK: - State

    var messages: [Message] = []
    var currentStreamingText: String = ""
    var currentThinkingText: String = ""
    var isStreaming: Bool = false
    var isThinking: Bool = false
    var isRecovering: Bool = false
    var isRestoringConversation: Bool = false
    var inputText: String = ""
    var selectedModel: ModelType = .gpt5_4 {
        didSet {
            if !selectedModel.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = selectedModel.defaultEffort
            }
            guard !isApplyingStoredConversationConfiguration else { return }
            syncConversationConfiguration()
        }
    }
    var reasoningEffort: ReasoningEffort = .high {
        didSet {
            guard selectedModel.availableEfforts.contains(reasoningEffort) else {
                reasoningEffort = selectedModel.defaultEffort
                return
            }
            guard !isApplyingStoredConversationConfiguration else { return }
            syncConversationConfiguration()
        }
    }
    var backgroundModeEnabled: Bool = false {
        didSet {
            guard !isApplyingStoredConversationConfiguration else { return }
            syncConversationConfiguration()
        }
    }
    var serviceTier: ServiceTier = .standard {
        didSet {
            guard !isApplyingStoredConversationConfiguration else { return }
            syncConversationConfiguration()
        }
    }
    var currentConversation: Conversation?
    var errorMessage: String?
    var showModelSelector: Bool = false
    var selectedImageData: Data?

    // Tool call state
    var activeToolCalls: [ToolCallInfo] = []
    var liveCitations: [URLCitation] = []
    var liveFilePathAnnotations: [FilePathAnnotation] = []

    // File attachments pending send
    var pendingAttachments: [FileAttachment] = []

    // File preview state
    var filePreviewURL: URL?
    var isDownloadingFile: Bool = false
    var fileDownloadError: String?

    // MARK: - Dependencies

    private let openAIService = OpenAIService()
    private let keychainService = KeychainService()
    private var modelContext: ModelContext

    // Stream invalidation token
    private var activeStreamID = UUID()

    // Draft message for real-time persistence during streaming
    private var draftMessage: Message?
    private var lastDraftSaveTime: Date = .distantPast
    private var lastSequenceNumber: Int?
    private var activeRequestModel: ModelType?
    private var activeRequestEffort: ReasoningEffort?
    private var activeRequestUsesBackgroundMode = false
    private var activeRequestServiceTier: ServiceTier = .standard
    private var isApplyingStoredConversationConfiguration = false
    private var didCompleteLaunchBootstrap = false

    // Background task
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // Recovery task
    private var recoveryTask: Task<Void, Never>?
    private var activeRecoveryMessageID: UUID?
    private var activeRecoveryResponseID: String?

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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

    var liveDraftMessageID: UUID? {
        guard let draft = draftMessage,
              messages.contains(where: { $0.id == draft.id })
        else {
            return nil
        }

        return draft.id
    }

    var shouldShowDetachedStreamingBubble: Bool {
        isStreaming && liveDraftMessageID == nil
    }

    var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set { serviceTier = newValue ? .flex : .standard }
    }

    // MARK: - Lifecycle Observers

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleEnterBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidEnterBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleReturnToForeground()
            }
        }
    }

    private func handleEnterBackground() {
        if isStreaming {
            saveDraftNow()

            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "StreamCompletion") { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.saveDraftNow()

                    self.activeStreamID = UUID()
                    self.openAIService.cancelStream()

                    if let draft = self.draftMessage {
                        if draft.usedBackgroundMode {
                            draft.isComplete = false
                            draft.conversation?.updatedAt = .now
                            self.upsertMessage(draft)
                            try? self.modelContext.save()
                        } else {
                            if draft.content.isEmpty {
                                draft.content = "[Response interrupted. Please try again.]"
                                draft.thinking = nil
                            }
                            draft.isComplete = true
                            draft.conversation?.updatedAt = .now
                            self.upsertMessage(draft)
                            try? self.modelContext.save()
                        }
                    }

                    self.clearLiveGenerationState(clearDraft: false)
                    self.isRecovering = false

                    self.endBackgroundTask()
                }
            }
        }

        if let conversation = currentConversation,
           conversation.title == "New Chat",
           messages.count >= 2 {
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "TitleGeneration")
            Task { @MainActor in
                await self.generateTitle()
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                }
            }
        }
    }

    private func handleDidEnterBackground() {
        guard isStreaming else { return }
        _ = detachBackgroundResponseIfPossible(reason: "background")
    }

    private func handleReturnToForeground() {
        guard didCompleteLaunchBootstrap else { return }

        endBackgroundTask()

        if isStreaming {
            #if DEBUG
            print("[Foreground] Cancelling stale stream and attempting recovery")
            #endif

            activeStreamID = UUID()
            openAIService.cancelStream()
            saveDraftNow()
            clearLiveGenerationState(clearDraft: false)
        }

        if let draft = activeIncompleteAssistantDraft() {
            if let responseId = draft.responseId,
               isRecoveryInFlight(for: draft.id, responseId: responseId) {
                restoreDraftState(from: draft)
                return
            }

            recoveryTask?.cancel()
            recoveryTask = nil

            restoreDraftState(from: draft)

            if let responseId = draft.responseId {
                recoverResponse(messageId: draft.id, responseId: responseId, preferStreamingResume: draft.usedBackgroundMode)
                return
            }

            if !draft.content.isEmpty {
                finalizeDraftAsPartial()
                return
            }

            removeEmptyDraft()
        }

        recoveryTask?.cancel()
        recoveryTask = nil

        Task { @MainActor in
            await recoverIncompleteMessagesInCurrentConversation()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - API Key

    var apiKey: String {
        keychainService.loadAPIKey() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    // MARK: - File Preview

    func handleSandboxLinkTap(sandboxURL: String, annotation: FilePathAnnotation?) {
        guard let annotation = annotation else {
            fileDownloadError = "Cannot download file: no file reference found."
            return
        }

        guard !apiKey.isEmpty else {
            fileDownloadError = "No API key configured."
            return
        }

        let fileId = annotation.fileId
        let suggestedFilename = extractFilename(from: sandboxURL)
        let key = apiKey

        isDownloadingFile = true
        fileDownloadError = nil

        Task { @MainActor in
            do {
                let localURL = try await FileDownloadService.shared.downloadFile(
                    fileId: fileId,
                    suggestedFilename: suggestedFilename,
                    apiKey: key
                )
                isDownloadingFile = false
                filePreviewURL = localURL
                HapticService.shared.impact(.light)
            } catch {
                isDownloadingFile = false
                fileDownloadError = error.localizedDescription
                HapticService.shared.notify(.error)
                #if DEBUG
                print("[FileDownload] Failed: \(error)")
                #endif
            }
        }
    }

    private func extractFilename(from sandboxURL: String) -> String? {
        let path: String
        if sandboxURL.hasPrefix("sandbox:") {
            path = String(sandboxURL.dropFirst("sandbox:".count))
        } else {
            path = sandboxURL
        }
        let filename = (path as NSString).lastPathComponent
        return filename.isEmpty ? nil : filename
    }

    // MARK: - Document Handling

    func handlePickedDocuments(_ urls: [URL]) {
        for url in urls {
            do {
                let metadata = try FileMetadata.from(url: url)
                let attachment = FileAttachment(
                    filename: metadata.filename,
                    fileSize: metadata.fileSize,
                    fileType: metadata.fileType,
                    localData: metadata.data,
                    uploadStatus: .pending
                )
                pendingAttachments.append(attachment)
            } catch {
                #if DEBUG
                print("[Documents] Failed to read file \(url.lastPathComponent): \(error)")
                #endif
            }
        }
    }

    func removePendingAttachment(_ attachment: FileAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    private func uploadPendingAttachments() async -> [FileAttachment] {
        var uploaded: [FileAttachment] = []

        for i in pendingAttachments.indices {
            pendingAttachments[i].uploadStatus = .uploading

            guard let data = pendingAttachments[i].localData else {
                pendingAttachments[i].uploadStatus = .failed
                continue
            }

            do {
                let fileId = try await openAIService.uploadFile(
                    data: data,
                    filename: pendingAttachments[i].filename,
                    apiKey: apiKey
                )

                pendingAttachments[i].openAIFileId = fileId
                pendingAttachments[i].uploadStatus = .uploaded
                uploaded.append(pendingAttachments[i])
            } catch {
                pendingAttachments[i].uploadStatus = .failed
                #if DEBUG
                print("[Upload] Failed to upload \(pendingAttachments[i].filename): \(error)")
                #endif
            }
        }

        return uploaded
    }

    // MARK: - Send Message

    func sendMessage() {
        guard !isStreaming else { return }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil || !pendingAttachments.isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Please add your OpenAI API key in Settings."
            return
        }

        let attachmentsToSend = pendingAttachments

        let userMessage = Message(
            role: .user,
            content: text,
            imageData: selectedImageData
        )

        if !attachmentsToSend.isEmpty {
            userMessage.fileAttachmentsData = FileAttachment.encode(attachmentsToSend)
        }

        if currentConversation == nil {
            let conversation = Conversation(
                model: selectedModel.rawValue,
                reasoningEffort: reasoningEffort.rawValue,
                backgroundModeEnabled: backgroundModeEnabled,
                serviceTierRawValue: serviceTier.rawValue
            )
            modelContext.insert(conversation)
            currentConversation = conversation
        }

        userMessage.conversation = currentConversation
        currentConversation?.messages.append(userMessage)
        currentConversation?.model = selectedModel.rawValue
        currentConversation?.reasoningEffort = reasoningEffort.rawValue
        currentConversation?.backgroundModeEnabled = backgroundModeEnabled
        currentConversation?.serviceTierRawValue = serviceTier.rawValue
        currentConversation?.updatedAt = .now
        messages.append(userMessage)

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save your message."
            return
        }

        inputText = ""
        selectedImageData = nil
        errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = currentConversation
        currentConversation?.messages.append(draft)
        try? modelContext.save()
        draftMessage = draft

        isStreaming = true
        isThinking = false
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        lastSequenceNumber = nil
        activeRequestModel = selectedModel
        activeRequestEffort = reasoningEffort
        activeRequestUsesBackgroundMode = backgroundModeEnabled
        activeRequestServiceTier = serviceTier

        HapticService.shared.impact(.light)

        if !attachmentsToSend.isEmpty {
            Task { @MainActor in
                let uploaded = await uploadPendingAttachments()
                if !uploaded.isEmpty {
                    userMessage.fileAttachmentsData = FileAttachment.encode(uploaded)
                    try? modelContext.save()
                }
                pendingAttachments = []
                startStreamingRequest()
            }
        } else {
            pendingAttachments = []
            startStreamingRequest()
        }
    }

    // MARK: - Core Streaming Logic

    private static let maxReconnectAttempts = 3
    private static let reconnectBaseDelay: UInt64 = 1_000_000_000

    private func startStreamingRequest(reconnectAttempt: Int = 0) {
        startDirectStreamingRequest(reconnectAttempt: reconnectAttempt)
    }

    private func startDirectStreamingRequest(reconnectAttempt: Int = 0) {
        let requestAPIKey = apiKey
        let requestModel = activeRequestModel ?? selectedModel
        let requestEffort = activeRequestEffort ?? reasoningEffort
        let requestBackgroundMode = activeRequestUsesBackgroundMode
        let requestServiceTier = activeRequestServiceTier

        let requestMessages = messages
            .filter { $0.isComplete || $0.role == .user }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map {
                APIMessage(
                    role: $0.role,
                    content: $0.content,
                    imageData: $0.imageData,
                    fileAttachments: $0.fileAttachments
                )
            }

        let streamID = UUID()
        activeStreamID = streamID

        Task { @MainActor in
            let stream = openAIService.streamChat(
                apiKey: requestAPIKey,
                messages: requestMessages,
                model: requestModel,
                reasoningEffort: requestEffort,
                backgroundModeEnabled: requestBackgroundMode,
                serviceTier: requestServiceTier
            )

            var receivedConnectionLost = false
            var didReceiveCompletedEvent = false
            var pendingRecoveryResponseId: String?
            var pendingRecoveryError: String?

            for await event in stream {
                guard activeStreamID == streamID else { break }

                switch applyStreamEvent(event, animated: true) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    finalizeDraft()

                case .terminalIncomplete(let message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    saveDraftNow()
                    if let responseId = draftMessage?.responseId {
                        pendingRecoveryResponseId = responseId
                    } else if !currentStreamingText.isEmpty {
                        finalizeDraftAsPartial()
                    } else {
                        removeEmptyDraft()
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    saveDraftNow()
                    #if DEBUG
                    print("[VM] Connection lost")
                    #endif

                case .error(let error):
                    saveDraftNow()

                    if let responseId = draftMessage?.responseId {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = error.localizedDescription
                        #if DEBUG
                        print("[VM] Stream error, attempting recovery: \(error.localizedDescription)")
                        #endif
                    } else if !currentStreamingText.isEmpty {
                        finalizeDraftAsPartial()
                        errorMessage = error.localizedDescription
                        HapticService.shared.notify(.error)
                    } else {
                        removeEmptyDraft()
                        errorMessage = error.localizedDescription
                        clearLiveGenerationState(clearDraft: true)
                        HapticService.shared.notify(.error)
                    }
                }
            }

            guard activeStreamID == streamID else {
                endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId,
               let draft = draftMessage {
                clearLiveGenerationState(clearDraft: false)
                if let pendingRecoveryError, !pendingRecoveryError.isEmpty {
                    errorMessage = pendingRecoveryError
                }
                recoverResponse(messageId: draft.id, responseId: responseId, preferStreamingResume: draft.usedBackgroundMode)
                endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let draft = draftMessage, let responseId = draft.responseId {
                    clearLiveGenerationState(clearDraft: false)
                    recoverResponse(messageId: draft.id, responseId: responseId, preferStreamingResume: draft.usedBackgroundMode)
                    endBackgroundTask()
                    return
                }

                let nextAttempt = reconnectAttempt + 1

                if nextAttempt < Self.maxReconnectAttempts {
                    let delay = Self.reconnectBaseDelay * UInt64(1 << reconnectAttempt)
                    #if DEBUG
                    print("[VM] Retrying full stream in \(Double(delay) / 1_000_000_000)s")
                    #endif

                    try? await Task.sleep(nanoseconds: delay)

                    guard activeStreamID == streamID else {
                        endBackgroundTask()
                        return
                    }

                    HapticService.shared.impact(.light)
                    startDirectStreamingRequest(reconnectAttempt: nextAttempt)
                    endBackgroundTask()
                    return
                }

                if !currentStreamingText.isEmpty {
                    finalizeDraftAsPartial()
                } else {
                    removeEmptyDraft()
                    errorMessage = "Connection lost. Please check your network and try again."
                    clearLiveGenerationState(clearDraft: true)
                    HapticService.shared.notify(.error)
                }

                endBackgroundTask()
                return
            }

            if isStreaming {
                if let draft = draftMessage, let responseId = draft.responseId {
                    saveDraftNow()
                    clearLiveGenerationState(clearDraft: false)
                    recoverResponse(messageId: draft.id, responseId: responseId, preferStreamingResume: draft.usedBackgroundMode)
                } else if !currentStreamingText.isEmpty {
                    finalizeDraftAsPartial()
                } else {
                    removeEmptyDraft()
                    clearLiveGenerationState(clearDraft: true)
                }
            }

            endBackgroundTask()
        }
    }

    // MARK: - Tool Call & Citation Persistence

    private func persistToolCallsAndCitations() {
        saveDraftNow()
    }

    // MARK: - Draft Persistence

    private func saveDraftIfNeeded() {
        let now = Date()
        let minimumInterval = activeRequestUsesBackgroundMode ? 0.25 : 2.0
        guard now.timeIntervalSince(lastDraftSaveTime) >= minimumInterval else { return }
        saveDraftNow()
    }

    private func saveDraftNow() {
        guard let draft = draftMessage else { return }
        draft.content = currentStreamingText
        draft.thinking = currentThinkingText.isEmpty ? nil : currentThinkingText
        draft.toolCallsData = ToolCallInfo.encode(activeToolCalls)
        draft.annotationsData = URLCitation.encode(liveCitations)
        draft.filePathAnnotationsData = FilePathAnnotation.encode(liveFilePathAnnotations)
        draft.lastSequenceNumber = lastSequenceNumber
        draft.usedBackgroundMode = activeRequestUsesBackgroundMode
        draft.conversation?.updatedAt = .now
        lastDraftSaveTime = Date()
        try? modelContext.save()
    }

    private func finalizeDraft() {
        guard let draft = draftMessage else {
            clearLiveGenerationState(clearDraft: true)
            isRecovering = false
            return
        }

        let finalText = currentStreamingText
        let finalThinking = currentThinkingText.isEmpty ? nil : currentThinkingText

        if finalText.isEmpty {
            removeEmptyDraft()
            clearLiveGenerationState(clearDraft: true)
            isRecovering = false
            return
        }

        draft.content = finalText
        draft.thinking = finalThinking
        draft.isComplete = true
        draft.lastSequenceNumber = nil
        draft.conversation?.updatedAt = .now

        // Persist file path annotations
        if !liveFilePathAnnotations.isEmpty {
            draft.filePathAnnotationsData = FilePathAnnotation.encode(liveFilePathAnnotations)
        }

        upsertMessage(draft)
        try? modelContext.save()

        clearLiveGenerationState(clearDraft: true)
        isRecovering = false

        if currentConversation?.title == "New Chat" && messages.count >= 2 {
            Task { @MainActor in
                await generateTitle()
            }
        }

        HapticService.shared.notify(.success)
    }

    private func finalizeDraftAsPartial() {
        guard let draft = draftMessage else { return }

        let finalText = currentStreamingText.isEmpty ? draft.content : currentStreamingText
        let finalThinking = currentThinkingText.isEmpty ? draft.thinking : currentThinkingText

        draft.content = finalText.isEmpty ? "[Response interrupted. Please try again.]" : finalText
        draft.thinking = finalThinking
        draft.isComplete = true
        draft.lastSequenceNumber = nil
        draft.conversation?.updatedAt = .now

        if !liveFilePathAnnotations.isEmpty {
            draft.filePathAnnotationsData = FilePathAnnotation.encode(liveFilePathAnnotations)
        }

        upsertMessage(draft)
        try? modelContext.save()

        clearLiveGenerationState(clearDraft: true)
        isRecovering = false
    }

    private func removeEmptyDraft() {
        guard let draft = draftMessage else { return }

        if let conversation = draft.conversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
            conversation.messages.remove(at: idx)
        }

        modelContext.delete(draft)
        try? modelContext.save()
        draftMessage = nil
    }

    // MARK: - Recovery

    private func recoverResponse(messageId: UUID, responseId: String, preferStreamingResume: Bool) {
        guard !apiKey.isEmpty else {
            isRecovering = false
            return
        }

        if isRecoveryInFlight(for: messageId, responseId: responseId) {
            return
        }

        recoveryTask?.cancel()
        errorMessage = nil
        isRecovering = true
        isStreaming = false
        isThinking = false
        activeRecoveryMessageID = messageId
        activeRecoveryResponseID = responseId

        if let message = findMessage(byId: messageId),
           !message.content.isEmpty,
           !messages.contains(where: { $0.id == messageId }) {
            upsertMessage(message)
        }

        let key = apiKey
        let service = openAIService
        let msgId = messageId
        let respId = responseId

        recoveryTask = Task { @MainActor in
            defer {
                if self.activeRecoveryMessageID == msgId && self.activeRecoveryResponseID == respId {
                    self.activeRecoveryMessageID = nil
                    self.activeRecoveryResponseID = nil
                }
                self.isRecovering = false
                self.isStreaming = false
                self.isThinking = false
            }

            guard let message = self.findMessage(byId: msgId) else { return }

            do {
                let result = try await service.fetchResponse(responseId: respId, apiKey: key)

                switch result.status {
                case .completed:
                    self.finishRecovery(
                        for: message,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message),
                        fallbackThinking: self.recoveryFallbackThinking(for: message)
                    )
                    return

                case .failed, .incomplete, .unknown:
                    self.errorMessage = result.errorMessage ?? "Response did not complete."
                    self.finishRecovery(
                        for: message,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message),
                        fallbackThinking: self.recoveryFallbackThinking(for: message)
                    )
                    return

                case .queued, .inProgress:
                    if preferStreamingResume,
                       message.usedBackgroundMode,
                       let lastSeq = message.lastSequenceNumber {
                        await self.startStreamingRecovery(messageId: msgId, responseId: respId, lastSeq: lastSeq, apiKey: key)
                        return
                    }

                    await self.pollResponseUntilTerminal(messageId: msgId, responseId: respId)
                    return
                }
            } catch {
                if self.handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: respId
                ) {
                    return
                }

                #if DEBUG
                print("[Recovery] Status fetch failed for \(respId): \(error.localizedDescription)")
                #endif
                await self.pollResponseUntilTerminal(messageId: msgId, responseId: respId)
            }
        }
    }

    private func startStreamingRecovery(
        messageId: UUID,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        guard let message = findMessage(byId: messageId) else { return }

        restoreDraftState(from: message)
        isRecovering = true
        isStreaming = true
        activeRequestUsesBackgroundMode = true

        let streamID = UUID()
        activeStreamID = streamID

        let stream = openAIService.streamRecovery(
            responseId: responseId,
            startingAfter: lastSeq,
            apiKey: apiKey,
            useDirectBaseURL: useDirectEndpoint
        )

        var finishedFromStream = false
        var encounteredRecoverableFailure = false
        var receivedAnyRecoveryEvent = false
        var gatewayResumeTimedOut = false
        let gatewayFallbackTask: Task<Void, Never>? = {
            guard FeatureFlags.useCloudflareGateway, !useDirectEndpoint else {
                return nil
            }

            return Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)

                guard self.activeStreamID == streamID, !receivedAnyRecoveryEvent else {
                    return
                }

                gatewayResumeTimedOut = true
                self.openAIService.cancelStream()
            }
        }()
        defer { gatewayFallbackTask?.cancel() }

        for await event in stream {
            guard activeStreamID == streamID else { return }
            receivedAnyRecoveryEvent = true
            gatewayFallbackTask?.cancel()

            switch applyStreamEvent(event, animated: false) {
            case .continued:
                break

            case .terminalCompleted:
                finishedFromStream = true
                finalizeDraft()

            case .terminalIncomplete(let message):
                errorMessage = message ?? "Response did not complete."
                saveDraftNow()
                encounteredRecoverableFailure = true

            case .connectionLost:
                saveDraftNow()
                encounteredRecoverableFailure = true

            case .error(let error):
                errorMessage = error.localizedDescription
                saveDraftNow()
                encounteredRecoverableFailure = true
            }
        }

        guard activeStreamID == streamID else { return }
        guard !finishedFromStream else { return }
        guard !Task.isCancelled else { return }

        clearLiveGenerationState(clearDraft: false)

        if FeatureFlags.useCloudflareGateway,
           !useDirectEndpoint,
           gatewayResumeTimedOut || !receivedAnyRecoveryEvent {
            #if DEBUG
            print("[Recovery] Gateway resume stalled for \(responseId); retrying direct")
            #endif
            await startStreamingRecovery(
                messageId: messageId,
                responseId: responseId,
                lastSeq: lastSeq,
                apiKey: apiKey,
                useDirectEndpoint: true
            )
            return
        }

        if encounteredRecoverableFailure || draftMessage?.responseId != nil {
            await pollResponseUntilTerminal(messageId: messageId, responseId: responseId)
        }
    }

    private func pollResponseUntilTerminal(messageId: UUID, responseId: String) async {
        guard !apiKey.isEmpty else { return }

        let key = apiKey
        var attempts = 0
        let maxAttempts = 180
        var lastResult: OpenAIResponseFetchResult?
        var lastError: String?

        while !Task.isCancelled && attempts < maxAttempts {
            attempts += 1

            do {
                let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: key)
                lastResult = result

                switch result.status {
                case .queued, .inProgress:
                    #if DEBUG
                    if attempts <= 3 || attempts % 10 == 0 {
                        print("[Recovery] Response still \(result.status.rawValue), attempt \(attempts)/\(maxAttempts)")
                    }
                    #endif
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue

                case .completed, .incomplete, .failed, .unknown:
                    if let message = findMessage(byId: messageId) {
                        if result.status == .failed || result.status == .incomplete {
                            errorMessage = result.errorMessage ?? "Response did not complete."
                        }
                        finishRecovery(
                            for: message,
                            result: result,
                            fallbackText: recoveryFallbackText(for: message),
                            fallbackThinking: recoveryFallbackThinking(for: message)
                        )
                    }
                    return
                }
            } catch {
                if let message = findMessage(byId: messageId),
                   handleUnrecoverableRecoveryError(error, for: message, responseId: responseId) {
                    return
                }

                lastError = error.localizedDescription
                #if DEBUG
                print("[Recovery] Poll error: \(lastError ?? "unknown"), attempt \(attempts)/\(maxAttempts)")
                #endif

                let delay: UInt64 = attempts < 10 ? 2_000_000_000 : 3_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        guard !Task.isCancelled else { return }

        if let message = findMessage(byId: messageId) {
            if let lastError, !lastError.isEmpty {
                errorMessage = lastError
            }
            finishRecovery(
                for: message,
                result: lastResult,
                fallbackText: recoveryFallbackText(for: message),
                fallbackThinking: recoveryFallbackThinking(for: message)
            )
        }

        #if DEBUG
        print("[Recovery] Finished with fallback after \(attempts) attempts. Last error: \(lastError ?? "none")")
        #endif
    }

    private func recoverIncompleteMessages() async {
        guard !apiKey.isEmpty else { return }

        await cleanupStaleDrafts()

        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId != nil
            }
        )

        guard let fetchedMessages = try? modelContext.fetch(descriptor) else { return }
        let activeDraftID = activeIncompleteAssistantDraft()?.id
        let currentConversationID = currentConversation?.id
        let incompleteMessages = fetchedMessages.filter {
            $0.id != activeDraftID && $0.conversation?.id != currentConversationID
        }
        guard !incompleteMessages.isEmpty else { return }

        #if DEBUG
        print("[Recovery] Found \(incompleteMessages.count) incomplete message(s) to recover")
        #endif

        isRecovering = true
        defer { isRecovering = false }

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }
            await recoverSingleMessage(message: message, responseId: responseId)
        }
    }

    private func cleanupStaleDrafts() async {
        let staleThreshold = Date().addingTimeInterval(-24 * 60 * 60)

        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false
            }
        )

        guard let staleMessages = try? modelContext.fetch(descriptor) else { return }

        var cleanedCount = 0

        for message in staleMessages {
            guard message.createdAt < staleThreshold else { continue }

            if message.content.isEmpty && message.responseId == nil {
                modelContext.delete(message)
                cleanedCount += 1
            } else {
                message.isComplete = true
                if message.content.isEmpty {
                    message.content = "[Response interrupted. Please try again.]"
                }
                cleanedCount += 1
            }
        }

        if cleanedCount > 0 {
            try? modelContext.save()
            #if DEBUG
            print("[Recovery] Cleaned up \(cleanedCount) stale draft(s)")
            #endif
        }
    }

    private func resendOrphanedDrafts() async {
        guard !apiKey.isEmpty else { return }

        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId == nil
            }
        )

        guard let orphanedDrafts = try? modelContext.fetch(descriptor) else { return }

        let draftsToResend = orphanedDrafts.filter { $0.role == .assistant && $0.content.isEmpty }

        #if DEBUG
        if !draftsToResend.isEmpty {
            print("[Recovery] Found \(draftsToResend.count) orphaned draft(s) to resend")
        }
        #endif

        let currentConversationID = currentConversation?.id

        for draft in draftsToResend {
            guard let conversation = draft.conversation else {
                modelContext.delete(draft)
                try? modelContext.save()
                continue
            }

            if let currentConversationID, conversation.id != currentConversationID {
                continue
            }

            let userMessages = conversation.messages
                .filter { $0.role == .user }
                .sorted { $0.createdAt < $1.createdAt }

            guard userMessages.last != nil else {
                modelContext.delete(draft)
                try? modelContext.save()
                continue
            }

            #if DEBUG
            print("[Recovery] Resending request for orphaned draft in conversation: \(conversation.title)")
            #endif

            currentConversation = conversation
            messages = visibleMessages(for: conversation)
                .filter { $0.id != draft.id }

            applyConversationConfiguration(from: conversation)

            if let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
                conversation.messages.remove(at: idx)
            }

            modelContext.delete(draft)
            try? modelContext.save()

            let newDraft = Message(
                role: .assistant,
                content: "",
                thinking: nil,
                lastSequenceNumber: nil,
                usedBackgroundMode: backgroundModeEnabled,
                isComplete: false
            )
            newDraft.conversation = currentConversation
            currentConversation?.messages.append(newDraft)
            try? modelContext.save()
            draftMessage = newDraft

            isStreaming = true
            isThinking = true
            isRecovering = true
            currentStreamingText = ""
            currentThinkingText = ""
            activeToolCalls = []
            liveCitations = []
            liveFilePathAnnotations = []
            lastSequenceNumber = nil
            activeRequestModel = selectedModel
            activeRequestEffort = reasoningEffort
            activeRequestUsesBackgroundMode = backgroundModeEnabled
            activeRequestServiceTier = serviceTier
            errorMessage = nil

            #if DEBUG
            print("[Recovery] Starting resend stream for conversation: \(conversation.title), messages count: \(messages.count)")
            #endif

            startStreamingRequest()
            return
        }
    }

    private func recoverIncompleteMessagesInCurrentConversation() async {
        guard !apiKey.isEmpty else { return }
        guard let conversation = currentConversation else { return }

        let incompleteMessages = conversation.messages.filter {
            $0.role == .assistant && !$0.isComplete && $0.responseId != nil
        }

        guard !incompleteMessages.isEmpty else { return }

        let sortedMessages = incompleteMessages.sorted { $0.createdAt < $1.createdAt }

        if let activeMessage = sortedMessages.last,
           let responseId = activeMessage.responseId {
            recoverResponse(
                messageId: activeMessage.id,
                responseId: responseId,
                preferStreamingResume: activeMessage.usedBackgroundMode
            )
        }

        for message in sortedMessages.dropLast() {
            guard let responseId = message.responseId else { continue }
            await recoverSingleMessage(message: message, responseId: responseId)
        }
    }

    private func recoverSingleMessage(message: Message, responseId: String) async {
        let key = apiKey
        var attempts = 0
        let maxAttempts = 180
        var lastResult: OpenAIResponseFetchResult?

        while !Task.isCancelled && attempts < maxAttempts {
            attempts += 1

            do {
                let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: key)
                lastResult = result

                switch result.status {
                case .queued, .inProgress:
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue

                case .completed, .incomplete, .failed, .unknown:
                    applyRecoveredResult(
                        result,
                        to: message,
                        fallbackText: message.content,
                        fallbackThinking: message.thinking
                    )
                    try? modelContext.save()
                    upsertMessage(message)

                    #if DEBUG
                    print("[Recovery] Recovered message \(message.id) with status \(result.status.rawValue)")
                    #endif
                    return
                }

            } catch {
                if handleUnrecoverableRecoveryError(error, for: message, responseId: responseId) {
                    return
                }

                let delay: UInt64 = attempts < 10 ? 2_000_000_000 : 3_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        guard !Task.isCancelled else { return }

        applyRecoveredResult(
            lastResult,
            to: message,
            fallbackText: message.content,
            fallbackThinking: message.thinking
        )
        try? modelContext.save()
        upsertMessage(message)
    }

    private func findMessage(byId id: UUID) -> Message? {
        if let msg = messages.first(where: { $0.id == id }) {
            return msg
        }

        if let draft = draftMessage, draft.id == id {
            return draft
        }

        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @discardableResult
    private func detachBackgroundResponseIfPossible(reason: String) -> Bool {
        guard
            isStreaming,
            let draft = draftMessage,
            draft.usedBackgroundMode,
            draft.responseId != nil
        else {
            return false
        }

        saveDraftNow()
        activeStreamID = UUID()
        openAIService.cancelStream()
        recoveryTask?.cancel()
        errorMessage = nil

        draft.isComplete = false
        draft.conversation?.updatedAt = .now
        upsertMessage(draft)
        try? modelContext.save()

        clearLiveGenerationState(clearDraft: true)
        isRecovering = false
        endBackgroundTask()

        #if DEBUG
        print("[Detach] Detached background response for \(reason)")
        #endif

        return true
    }

    // MARK: - Stop Generation

    func stopGeneration(savePartial: Bool = true) {
        let pendingBackgroundCancellation: (responseId: String, messageId: UUID)? = {
            guard
                let draft = draftMessage,
                draft.usedBackgroundMode,
                let responseId = draft.responseId
            else {
                return nil
            }

            return (responseId, draft.id)
        }()

        activeStreamID = UUID()
        openAIService.cancelStream()
        recoveryTask?.cancel()
        errorMessage = nil

        if savePartial && !currentStreamingText.isEmpty {
            persistToolCallsAndCitations()
            finalizeDraft()
        } else if let draft = draftMessage {
            if !currentStreamingText.isEmpty {
                draft.content = currentStreamingText
            }
            if !currentThinkingText.isEmpty {
                draft.thinking = currentThinkingText
            }
            if !draft.content.isEmpty {
                draft.isComplete = true
                try? modelContext.save()
                upsertMessage(draft)
                clearLiveGenerationState(clearDraft: true)
            } else {
                removeEmptyDraft()
                clearLiveGenerationState(clearDraft: true)
            }
        } else {
            removeEmptyDraft()
            clearLiveGenerationState(clearDraft: true)
        }

        isRecovering = false
        endBackgroundTask()
        HapticService.shared.impact(.medium)

        if let pendingBackgroundCancellation {
            Task { @MainActor in
                await self.cancelBackgroundResponseAndSync(
                    responseId: pendingBackgroundCancellation.responseId,
                    messageId: pendingBackgroundCancellation.messageId
                )
            }
        }
    }

    // MARK: - New Chat

    func startNewChat() {
        if isStreaming {
            if !detachBackgroundResponseIfPossible(reason: "new-chat") {
                stopGeneration(savePartial: true)
            }
        }

        recoveryTask?.cancel()

        currentConversation = nil
        messages = []
        currentStreamingText = ""
        currentThinkingText = ""
        inputText = ""
        errorMessage = nil
        selectedImageData = nil
        pendingAttachments = []
        isThinking = false
        isRecovering = false
        draftMessage = nil
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        lastSequenceNumber = nil
        activeRequestUsesBackgroundMode = false
        filePreviewURL = nil
        fileDownloadError = nil
        loadDefaultsFromSettings()
        HapticService.shared.selection()
    }

    // MARK: - Regenerate Last Response

    func regenerateMessage(_ message: Message) {
        guard !isStreaming else { return }
        guard message.role == .assistant else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Please add your OpenAI API key in Settings."
            return
        }

        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: index)
        }

        if let conversation = currentConversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        modelContext.delete(message)
        try? modelContext.save()

        errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = currentConversation
        currentConversation?.messages.append(draft)
        try? modelContext.save()
        draftMessage = draft

        isStreaming = true
        isThinking = false
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        lastSequenceNumber = nil
        activeRequestModel = selectedModel
        activeRequestEffort = reasoningEffort
        activeRequestUsesBackgroundMode = backgroundModeEnabled
        activeRequestServiceTier = serviceTier

        HapticService.shared.impact(.medium)

        startStreamingRequest()
    }

    // MARK: - Load Conversation

    func loadConversation(_ conversation: Conversation) {
        if isStreaming {
            if !detachBackgroundResponseIfPossible(reason: "switch-conversation") {
                stopGeneration(savePartial: true)
            }
        }

        recoveryTask?.cancel()

        currentConversation = conversation
        messages = visibleMessages(for: conversation)

        applyConversationConfiguration(from: conversation)

        currentStreamingText = ""
        currentThinkingText = ""
        errorMessage = nil
        isThinking = false
        isRecovering = false
        draftMessage = nil
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        lastSequenceNumber = nil
        activeRequestUsesBackgroundMode = false
        pendingAttachments = []
        filePreviewURL = nil
        fileDownloadError = nil

        Task { @MainActor in
            await recoverIncompleteMessagesInCurrentConversation()
        }
    }

    // MARK: - Restore Last Conversation

    private func restoreLastConversationIfAvailable() {
        var descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let conversations = try? modelContext.fetch(descriptor),
           let lastConversation = conversations.first,
           !lastConversation.messages.isEmpty {
            currentConversation = lastConversation
            messages = visibleMessages(for: lastConversation)

            applyConversationConfiguration(from: lastConversation)

            #if DEBUG
            print("[Restore] Loaded last conversation: \(lastConversation.title) (\(messages.count) messages)")
            #endif
        }
    }

    private func generateTitlesForUntitledConversations() async {
        guard !apiKey.isEmpty else { return }

        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { conversation in
                conversation.title == "New Chat"
            }
        )

        guard let untitled = try? modelContext.fetch(descriptor) else { return }

        for conversation in untitled {
            guard conversation.messages.count >= 2 else { continue }

            let preview = conversation.messages
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(4)
                .map { "\($0.roleRawValue): \($0.content.prefix(200))" }
                .joined(separator: "\n")

            do {
                let title = try await openAIService.generateTitle(
                    for: preview,
                    apiKey: apiKey
                )
                conversation.title = title
                try? modelContext.save()

                if conversation.id == currentConversation?.id {
                    currentConversation?.title = title
                }

                #if DEBUG
                print("[Title] Generated title for conversation \(conversation.id): \(title)")
                #endif
            } catch {
                #if DEBUG
                print("[Title] Failed to generate title: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Helpers

    private enum StreamEventDisposition {
        case continued
        case terminalCompleted
        case terminalIncomplete(String?)
        case connectionLost
        case error(OpenAIServiceError)
    }

    private func loadDefaultsFromSettings() {
        if let savedModel = UserDefaults.standard.string(forKey: StorageKeys.defaultModel),
           let model = ModelType(rawValue: savedModel) {
            selectedModel = model
        } else {
            selectedModel = .gpt5_4_pro
        }

        if let savedEffort = UserDefaults.standard.string(forKey: StorageKeys.defaultEffort),
           let effort = ReasoningEffort(rawValue: savedEffort) {
            reasoningEffort = effort
        } else {
            reasoningEffort = .xhigh
        }

        if let savedBackgroundMode = UserDefaults.standard.object(forKey: StorageKeys.defaultBackgroundModeEnabled) as? Bool {
            backgroundModeEnabled = savedBackgroundMode
        } else {
            backgroundModeEnabled = false
        }

        if let savedServiceTier = UserDefaults.standard.string(forKey: StorageKeys.defaultServiceTier),
           let storedTier = ServiceTier(rawValue: savedServiceTier) {
            serviceTier = storedTier
        } else {
            serviceTier = .standard
        }

        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
        }
    }

    private func applyConversationConfiguration(from conversation: Conversation) {
        let model = ModelType(rawValue: conversation.model) ?? .gpt5_4
        let storedEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        let resolvedEffort = model.availableEfforts.contains(storedEffort) ? storedEffort : model.defaultEffort
        let resolvedTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard

        isApplyingStoredConversationConfiguration = true
        selectedModel = model
        reasoningEffort = resolvedEffort
        backgroundModeEnabled = conversation.backgroundModeEnabled
        serviceTier = resolvedTier
        isApplyingStoredConversationConfiguration = false
    }

    private func visibleMessages(for conversation: Conversation) -> [Message] {
        conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .filter { !shouldHideMessage($0) }
    }

    private func shouldHideMessage(_ message: Message) -> Bool {
        guard message.role == .assistant, !message.isComplete else {
            return false
        }

        if message.responseId != nil {
            return false
        }

        if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if let thinking = message.thinking,
           !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if !message.toolCalls.isEmpty || !message.annotations.isEmpty || !message.filePathAnnotations.isEmpty {
            return false
        }

        return true
    }

    private func isRecoveryInFlight(for messageId: UUID, responseId: String) -> Bool {
        activeRecoveryMessageID == messageId &&
        activeRecoveryResponseID == responseId &&
        recoveryTask != nil
    }

    @discardableResult
    private func handleUnrecoverableRecoveryError(
        _ error: Error,
        for message: Message,
        responseId: String
    ) -> Bool {
        guard case let OpenAIServiceError.httpError(statusCode, responseBody) = error,
              statusCode == 404 else {
            return false
        }

        let fallbackText: String

        if message.usedBackgroundMode {
            errorMessage = "This response is no longer resumable."
            fallbackText = recoveryFallbackText(for: message)
        } else {
            errorMessage = nil
            fallbackText = interruptedResponseFallbackText(for: message)
        }

        #if DEBUG
        print("[Recovery] Response \(responseId) is no longer available: \(responseBody)")
        #endif

        finishRecovery(
            for: message,
            result: nil,
            fallbackText: fallbackText,
            fallbackThinking: recoveryFallbackThinking(for: message)
        )
        return true
    }

    private func syncConversationConfiguration() {
        guard let currentConversation else { return }
        currentConversation.model = selectedModel.rawValue
        currentConversation.reasoningEffort = reasoningEffort.rawValue
        currentConversation.backgroundModeEnabled = backgroundModeEnabled
        currentConversation.serviceTierRawValue = serviceTier.rawValue
        currentConversation.updatedAt = .now
        try? modelContext.save()
    }

    private func upsertMessage(_ message: Message) {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        } else {
            messages.append(message)
            messages.sort { $0.createdAt < $1.createdAt }
        }
    }

    private func clearLiveGenerationState(clearDraft: Bool) {
        currentStreamingText = ""
        currentThinkingText = ""
        isStreaming = false
        isThinking = false
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        lastSequenceNumber = nil
        activeRequestModel = nil
        activeRequestEffort = nil
        activeRequestUsesBackgroundMode = false
        activeRequestServiceTier = .standard
        if clearDraft {
            draftMessage = nil
        }
    }

    private func applyRecoveredResult(
        _ result: OpenAIResponseFetchResult?,
        to message: Message,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        if let result {
            if !result.text.isEmpty {
                message.content = result.text
            }
            if let thinking = result.thinking, !thinking.isEmpty {
                message.thinking = thinking
            }
            if !result.toolCalls.isEmpty {
                message.toolCallsData = ToolCallInfo.encode(result.toolCalls)
            }
            if !result.annotations.isEmpty {
                message.annotationsData = URLCitation.encode(result.annotations)
            }
            if !result.filePathAnnotations.isEmpty {
                message.filePathAnnotationsData = FilePathAnnotation.encode(result.filePathAnnotations)
            }
        }

        if message.content.isEmpty {
            message.content = fallbackText.isEmpty ? "[Response interrupted. Please try again.]" : fallbackText
        }

        if (message.thinking?.isEmpty ?? true),
           let fallbackThinking,
           !fallbackThinking.isEmpty {
            message.thinking = fallbackThinking
        }

        message.isComplete = true
        message.lastSequenceNumber = nil
        message.conversation?.updatedAt = .now
    }

    private func finishRecovery(
        for message: Message,
        result: OpenAIResponseFetchResult?,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        applyRecoveredResult(
            result,
            to: message,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )

        try? modelContext.save()
        upsertMessage(message)

        if draftMessage?.id == message.id {
            draftMessage = nil
        }

        clearLiveGenerationState(clearDraft: false)

        if currentConversation?.title == "New Chat" && messages.count >= 2 {
            Task { @MainActor in
                await generateTitle()
            }
        }

        HapticService.shared.notify(.success)
    }

    private func recoveryFallbackText(for message: Message) -> String {
        !currentStreamingText.isEmpty ? currentStreamingText : message.content
    }

    private func recoveryFallbackThinking(for message: Message) -> String? {
        !currentThinkingText.isEmpty ? currentThinkingText : message.thinking
    }

    private func interruptedResponseFallbackText(for message: Message) -> String {
        let interruptionNotice = "Response interrupted because the app was closed before completion."
        let baseText = recoveryFallbackText(for: message)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseText.isEmpty else {
            return interruptionNotice
        }

        if baseText.contains(interruptionNotice) {
            return baseText
        }

        return "\(baseText)\n\n\(interruptionNotice)"
    }

    private func restoreDraftState(from message: Message) {
        draftMessage = message
        currentStreamingText = message.content
        currentThinkingText = message.thinking ?? ""
        activeToolCalls = message.toolCalls
        liveCitations = message.annotations
        liveFilePathAnnotations = message.filePathAnnotations
        lastSequenceNumber = message.lastSequenceNumber
        activeRequestUsesBackgroundMode = message.usedBackgroundMode
        upsertMessage(message)
    }

    private func applyStreamEvent(_ event: StreamEvent, animated: Bool) -> StreamEventDisposition {
        switch event {
        case .responseCreated(let responseId):
            if let draft = draftMessage {
                draft.responseId = responseId
                draft.usedBackgroundMode = activeRequestUsesBackgroundMode
                try? modelContext.save()
                #if DEBUG
                print("[VM] Saved responseId: \(responseId)")
                #endif
            }
            return .continued

        case .sequenceUpdate(let sequence):
            if let lastSequenceNumber {
                self.lastSequenceNumber = max(lastSequenceNumber, sequence)
            } else {
                self.lastSequenceNumber = sequence
            }
            saveDraftIfNeeded()
            return .continued

        case .textDelta(let delta):
            if isThinking {
                withAnimation(.easeOut(duration: 0.2)) {
                    isThinking = false
                }
            }
            currentStreamingText += delta
            saveDraftIfNeeded()
            return .continued

        case .thinkingDelta(let delta):
            currentThinkingText += delta
            saveDraftIfNeeded()
            return .continued

        case .thinkingStarted:
            withAnimation(.easeIn(duration: 0.2)) {
                isThinking = true
            }
            return .continued

        case .thinkingFinished:
            withAnimation(.easeOut(duration: 0.2)) {
                isThinking = false
            }
            saveDraftNow()
            return .continued

        case .webSearchStarted(let callId):
            startToolCallIfNeeded(id: callId, type: .webSearch, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .webSearchSearching(let callId):
            setToolCallStatus(callId, status: .searching, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .webSearchCompleted(let callId):
            setToolCallStatus(callId, status: .completed, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .codeInterpreterStarted(let callId):
            startToolCallIfNeeded(id: callId, type: .codeInterpreter, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .codeInterpreterInterpreting(let callId):
            setToolCallStatus(callId, status: .interpreting, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .codeInterpreterCodeDelta(let callId, let codeDelta):
            appendToolCodeDelta(callId, delta: codeDelta)
            saveDraftIfNeeded()
            return .continued

        case .codeInterpreterCodeDone(let callId, let fullCode):
            setToolCode(callId, code: fullCode)
            saveDraftIfNeeded()
            return .continued

        case .codeInterpreterCompleted(let callId):
            setToolCallStatus(callId, status: .completed, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .fileSearchStarted(let callId):
            startToolCallIfNeeded(id: callId, type: .fileSearch, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .fileSearchSearching(let callId):
            setToolCallStatus(callId, status: .fileSearching, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .fileSearchCompleted(let callId):
            setToolCallStatus(callId, status: .completed, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .annotationAdded(let citation):
            addLiveCitationIfNeeded(citation, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .filePathAnnotationAdded(let annotation):
            addLiveFilePathAnnotationIfNeeded(annotation, animated: animated)
            saveDraftIfNeeded()
            return .continued

        case .completed(let fullText, let fullThinking, let filePathAnns):
            if !fullText.isEmpty {
                currentStreamingText = fullText
            }
            if let fullThinking, !fullThinking.isEmpty {
                currentThinkingText = fullThinking
            }
            if let filePathAnns, !filePathAnns.isEmpty {
                liveFilePathAnnotations = filePathAnns
            }
            saveDraftNow()
            return .terminalCompleted

        case .incomplete(let fullText, let fullThinking, let filePathAnns, let message):
            if !fullText.isEmpty {
                currentStreamingText = fullText
            }
            if let fullThinking, !fullThinking.isEmpty {
                currentThinkingText = fullThinking
            }
            if let filePathAnns, !filePathAnns.isEmpty {
                liveFilePathAnnotations = filePathAnns
            }
            saveDraftNow()
            return .terminalIncomplete(message)

        case .connectionLost:
            return .connectionLost

        case .error(let error):
            return .error(error)
        }
    }

    private func cancelBackgroundResponseAndSync(responseId: String, messageId: UUID) async {
        guard !apiKey.isEmpty else { return }

        do {
            try await openAIService.cancelResponse(responseId: responseId, apiKey: apiKey)
        } catch {
            #if DEBUG
            print("[Stop] Background cancel failed for \(responseId): \(error.localizedDescription)")
            #endif
        }

        do {
            let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: apiKey)

            switch result.status {
            case .queued, .inProgress:
                await pollResponseUntilTerminal(messageId: messageId, responseId: responseId)

            case .completed, .incomplete, .failed, .unknown:
                guard let message = findMessage(byId: messageId) else { return }
                applyRecoveredResult(
                    result,
                    to: message,
                    fallbackText: message.content,
                    fallbackThinking: message.thinking
                )
                try? modelContext.save()
                upsertMessage(message)
            }
        } catch {
            #if DEBUG
            print("[Stop] Failed to refresh cancelled response \(responseId): \(error.localizedDescription)")
            #endif
        }
    }

    private func generateTitle() async {
        guard let conversation = currentConversation else { return }

        let preview = messages.prefix(4).map { msg in
            "\(msg.role.rawValue): \(msg.content.prefix(200))"
        }.joined(separator: "\n")

        do {
            let title = try await openAIService.generateTitle(
                for: preview,
                apiKey: apiKey
            )
            conversation.title = title
            try? modelContext.save()
        } catch {
            // Non-critical
        }
    }

    private func activeIncompleteAssistantDraft() -> Message? {
        if let draft = draftMessage, !draft.isComplete, draft.role == .assistant {
            return draft
        }

        return currentConversation?.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }

    private func animateIfNeeded(_ shouldAnimate: Bool, animation: Animation, _ updates: () -> Void) {
        if shouldAnimate {
            withAnimation(animation, updates)
        } else {
            updates()
        }
    }

    private func startToolCallIfNeeded(id: String, type: ToolCallType, animated: Bool) {
        guard !activeToolCalls.contains(where: { $0.id == id }) else { return }

        let insert = {
            self.activeToolCalls.append(
                ToolCallInfo(
                    id: id,
                    type: type,
                    status: .inProgress
                )
            )
        }

        animateIfNeeded(animated, animation: .spring(duration: 0.3), insert)
    }

    private func setToolCallStatus(_ id: String, status: ToolCallStatus, animated: Bool) {
        guard let idx = activeToolCalls.firstIndex(where: { $0.id == id }) else { return }

        let update = {
            self.activeToolCalls[idx].status = status
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), update)
    }

    private func appendToolCodeDelta(_ id: String, delta: String) {
        guard let idx = activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        let existing = activeToolCalls[idx].code ?? ""
        activeToolCalls[idx].code = existing + delta
    }

    private func setToolCode(_ id: String, code: String) {
        guard let idx = activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        activeToolCalls[idx].code = code
    }

    private func addLiveCitationIfNeeded(_ citation: URLCitation, animated: Bool) {
        guard !liveCitations.contains(where: { $0.id == citation.id }) else { return }

        let insert = {
            self.liveCitations.append(citation)
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), insert)
    }

    private func addLiveFilePathAnnotationIfNeeded(_ annotation: FilePathAnnotation, animated: Bool) {
        guard !liveFilePathAnnotations.contains(where: { $0.fileId == annotation.fileId }) else { return }

        let insert = {
            self.liveFilePathAnnotations.append(annotation)
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), insert)
    }
}
