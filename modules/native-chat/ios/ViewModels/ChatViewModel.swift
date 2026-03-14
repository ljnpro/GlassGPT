import SwiftUI
import SwiftData
import UIKit

@Observable
@MainActor
final class ChatViewModel {

    private enum RecoveryPhase: Equatable {
        case idle
        case checkingStatus
        case streamResuming
        case pollingTerminal
    }

    @MainActor
    private final class ResponseSession {
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

    // Visible live session state
    private var draftMessage: Message?
    private var lastSequenceNumber: Int?
    private var activeRequestModel: ModelType?
    private var activeRequestEffort: ReasoningEffort?
    private var activeRequestUsesBackgroundMode = false
    private var activeRequestServiceTier: ServiceTier = .standard
    private var isApplyingStoredConversationConfiguration = false
    private var didCompleteLaunchBootstrap = false
    private var visibleSessionMessageID: UUID?
    private var visibleRecoveryPhase: RecoveryPhase = .idle
    private var activeResponseSessions: [UUID: ResponseSession] = [:]

    // Background task
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

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

    private var currentVisibleSession: ResponseSession? {
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
        if !activeResponseSessions.isEmpty {
            for session in activeResponseSessions.values {
                saveSessionNow(session)
            }

            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "StreamCompletion") { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.suspendActiveSessionsForAppBackground()
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
        guard !activeResponseSessions.isEmpty else { return }
        suspendActiveSessionsForAppBackground()
    }

    private func handleReturnToForeground() {
        guard didCompleteLaunchBootstrap else { return }

        endBackgroundTask()
        refreshVisibleBindingForCurrentConversation()

        Task { @MainActor in
            await self.recoverIncompleteMessagesInCurrentConversation()
            await self.recoverIncompleteMessages()
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

        guard let session = makeStreamingSession(for: draft) else {
            errorMessage = "Failed to start response session."
            return
        }

        registerSession(session, visible: true)
        session.isStreaming = true
        session.isThinking = false
        syncVisibleState(from: session)

        HapticService.shared.impact(.light)

        if !attachmentsToSend.isEmpty {
            Task { @MainActor in
                let uploaded = await uploadPendingAttachments()
                if !uploaded.isEmpty {
                    userMessage.fileAttachmentsData = FileAttachment.encode(uploaded)
                    try? modelContext.save()
                }
                pendingAttachments = []
                self.startStreamingRequest(for: session)
            }
        } else {
            pendingAttachments = []
            startStreamingRequest(for: session)
        }
    }

    // MARK: - Core Streaming Logic

    private static let maxReconnectAttempts = 3
    private static let reconnectBaseDelay: UInt64 = 1_000_000_000

    private func startStreamingRequest(reconnectAttempt: Int = 0) {
        guard let session = currentVisibleSession else { return }
        startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }

    private func startStreamingRequest(for session: ResponseSession, reconnectAttempt: Int = 0) {
        startDirectStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }

    private func startDirectStreamingRequest(for session: ResponseSession, reconnectAttempt: Int = 0) {
        guard let requestMessages = session.requestMessages else { return }

        let requestAPIKey = apiKey
        let streamID = UUID()
        session.activeStreamID = streamID
        session.isStreaming = true
        setRecoveryPhase(.idle, for: session)
        syncVisibleState(from: session)

        session.task?.cancel()
        session.task = Task { @MainActor in
            let stream = session.service.streamChat(
                apiKey: requestAPIKey,
                messages: requestMessages,
                model: session.requestModel,
                reasoningEffort: session.requestEffort,
                backgroundModeEnabled: session.requestUsesBackgroundMode,
                serviceTier: session.requestServiceTier
            )

            var receivedConnectionLost = false
            var didReceiveCompletedEvent = false
            var pendingRecoveryResponseId: String?
            var pendingRecoveryError: String?

            for await event in stream {
                guard self.isSessionActive(session), session.activeStreamID == streamID else { break }

                switch self.applyStreamEvent(event, to: session, animated: self.visibleSessionMessageID == session.messageID) {
                case .continued:
                    break

                case .terminalCompleted:
                    didReceiveCompletedEvent = true
                    self.finalizeSession(session)

                case .terminalIncomplete(let message):
                    pendingRecoveryError = message ?? "Response was incomplete."
                    self.saveSessionNow(session)
                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                    } else if !session.currentText.isEmpty {
                        self.finalizeSessionAsPartial(session)
                    } else if let message = self.findMessage(byId: session.messageID) {
                        self.removeEmptyMessage(message, for: session)
                    }

                case .connectionLost:
                    receivedConnectionLost = true
                    self.saveSessionNow(session)
                    #if DEBUG
                    print("[VM] Connection lost for session \(session.messageID)")
                    #endif

                case .error(let error):
                    self.saveSessionNow(session)

                    if let responseId = session.responseId {
                        pendingRecoveryResponseId = responseId
                        pendingRecoveryError = error.localizedDescription
                        #if DEBUG
                        print("[VM] Stream error, attempting recovery: \(error.localizedDescription)")
                        #endif
                    } else if !session.currentText.isEmpty {
                        self.finalizeSessionAsPartial(session)
                        if self.visibleSessionMessageID == session.messageID {
                            self.errorMessage = error.localizedDescription
                            HapticService.shared.notify(.error)
                        }
                    } else if let message = self.findMessage(byId: session.messageID) {
                        self.removeEmptyMessage(message, for: session)
                        if self.visibleSessionMessageID == session.messageID {
                            self.errorMessage = error.localizedDescription
                            self.clearLiveGenerationState(clearDraft: true)
                            HapticService.shared.notify(.error)
                        }
                    }
                }
            }

            guard self.isSessionActive(session), session.activeStreamID == streamID else {
                self.endBackgroundTask()
                return
            }

            if didReceiveCompletedEvent {
                self.endBackgroundTask()
                return
            }

            if let responseId = pendingRecoveryResponseId {
                session.isStreaming = false
                setRecoveryPhase(.checkingStatus, for: session)
                if self.visibleSessionMessageID == session.messageID,
                   let pendingRecoveryError,
                   !pendingRecoveryError.isEmpty {
                    self.errorMessage = pendingRecoveryError
                }
                self.syncVisibleState(from: session)
                self.recoverResponse(
                    messageId: session.messageID,
                    responseId: responseId,
                    preferStreamingResume: session.requestUsesBackgroundMode
                )
                self.endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let responseId = session.responseId {
                    session.isStreaming = false
                    setRecoveryPhase(.checkingStatus, for: session)
                    self.syncVisibleState(from: session)
                    self.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.requestUsesBackgroundMode
                    )
                    self.endBackgroundTask()
                    return
                }

                let nextAttempt = reconnectAttempt + 1

                if nextAttempt < Self.maxReconnectAttempts {
                    let delay = Self.reconnectBaseDelay * UInt64(1 << reconnectAttempt)
                    #if DEBUG
                    print("[VM] Retrying full stream in \(Double(delay) / 1_000_000_000)s")
                    #endif

                    try? await Task.sleep(nanoseconds: delay)

                    guard self.isSessionActive(session), session.activeStreamID == streamID else {
                        self.endBackgroundTask()
                        return
                    }

                    HapticService.shared.impact(.light)
                    self.startDirectStreamingRequest(for: session, reconnectAttempt: nextAttempt)
                    self.endBackgroundTask()
                    return
                }

                if !session.currentText.isEmpty {
                    self.finalizeSessionAsPartial(session)
                } else if let message = self.findMessage(byId: session.messageID) {
                    self.removeEmptyMessage(message, for: session)
                    if self.visibleSessionMessageID == session.messageID {
                        self.errorMessage = "Connection lost. Please check your network and try again."
                        self.clearLiveGenerationState(clearDraft: true)
                        HapticService.shared.notify(.error)
                    }
                }

                self.endBackgroundTask()
                return
            }

            if session.isStreaming {
                if let responseId = session.responseId {
                    self.saveSessionNow(session)
                    session.isStreaming = false
                    setRecoveryPhase(.checkingStatus, for: session)
                    self.syncVisibleState(from: session)
                    self.recoverResponse(
                        messageId: session.messageID,
                        responseId: responseId,
                        preferStreamingResume: session.requestUsesBackgroundMode
                    )
                } else if !session.currentText.isEmpty {
                    self.finalizeSessionAsPartial(session)
                } else if let message = self.findMessage(byId: session.messageID) {
                    self.removeEmptyMessage(message, for: session)
                    if self.visibleSessionMessageID == session.messageID {
                        self.clearLiveGenerationState(clearDraft: true)
                    }
                }
            }

            self.endBackgroundTask()
        }
    }

    // MARK: - Tool Call & Citation Persistence

    private func persistToolCallsAndCitations() {
        guard let session = currentVisibleSession else { return }
        saveSessionNow(session)
    }

    // MARK: - Draft Persistence

    private func saveDraftIfNeeded() {
        guard let session = currentVisibleSession else { return }
        saveSessionIfNeeded(session)
    }

    private func saveDraftNow() {
        guard let session = currentVisibleSession else { return }
        saveSessionNow(session)
    }

    private func finalizeDraft() {
        guard let session = currentVisibleSession else {
            clearLiveGenerationState(clearDraft: true)
            setVisibleRecoveryPhase(.idle)
            return
        }

        finalizeSession(session)
    }

    private func finalizeDraftAsPartial() {
        guard let session = currentVisibleSession else { return }
        finalizeSessionAsPartial(session)
    }

    private func removeEmptyDraft() {
        guard
            let session = currentVisibleSession,
            let draft = draftMessage
        else {
            return
        }

        removeEmptyMessage(draft, for: session)
    }

    // MARK: - Recovery

    private func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        guard !apiKey.isEmpty else {
            return
        }

        guard let message = findMessage(byId: messageId) else { return }

        let session: ResponseSession
        if let existing = activeResponseSessions[messageId] {
            session = existing
        } else if let created = makeRecoverySession(for: message) {
            session = created
            registerSession(created, visible: visible)
        } else {
            return
        }

        if isSessionActive(session),
           session.task != nil,
           session.responseId == responseId {
            if visible {
                bindVisibleSession(messageID: messageId)
            }
            return
        }

        session.responseId = responseId
        setRecoveryPhase(.checkingStatus, for: session)
        session.isStreaming = false
        session.isThinking = false

        if visible {
            errorMessage = nil
            bindVisibleSession(messageID: messageId)
        }

        session.task?.cancel()

        session.task = Task { @MainActor in
            guard self.isSessionActive(session) else { return }

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: self.apiKey)

                switch result.status {
                case .completed:
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )
                    return

                case .failed, .incomplete, .unknown:
                    if visible {
                        self.errorMessage = result.errorMessage ?? "Response did not complete."
                    }
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )
                    return

                case .queued, .inProgress:
                    if preferStreamingResume,
                       message.usedBackgroundMode,
                       let lastSeq = message.lastSequenceNumber {
                        await self.startStreamingRecovery(
                            session: session,
                            responseId: responseId,
                            lastSeq: lastSeq,
                            apiKey: self.apiKey
                        )
                        return
                    }

                    await self.pollResponseUntilTerminal(session: session, responseId: responseId)
                    return
                }
            } catch {
                if self.handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: visible
                ) {
                    return
                }

                #if DEBUG
                print("[Recovery] Status fetch failed for \(responseId): \(error.localizedDescription)")
                #endif
                await self.pollResponseUntilTerminal(session: session, responseId: responseId)
            }
        }
    }

    private func startStreamingRecovery(
        session: ResponseSession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        let streamID = UUID()
        session.activeStreamID = streamID
        setRecoveryPhase(.streamResuming, for: session)
        session.isStreaming = true
        session.isThinking = false
        syncVisibleState(from: session)

        let stream = session.service.streamRecovery(
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

                guard self.isSessionActive(session), session.activeStreamID == streamID, !receivedAnyRecoveryEvent else {
                    return
                }

                gatewayResumeTimedOut = true
                session.service.cancelStream()
            }
        }()
        defer { gatewayFallbackTask?.cancel() }

        for await event in stream {
            guard isSessionActive(session), session.activeStreamID == streamID else { return }
            receivedAnyRecoveryEvent = true
            gatewayFallbackTask?.cancel()

            switch applyStreamEvent(event, to: session, animated: visibleSessionMessageID == session.messageID) {
            case .continued:
                break

            case .terminalCompleted:
                finishedFromStream = true
                finalizeSession(session)

            case .terminalIncomplete(let message):
                if visibleSessionMessageID == session.messageID {
                    errorMessage = message ?? "Response did not complete."
                }
                saveSessionNow(session)
                encounteredRecoverableFailure = true

            case .connectionLost:
                saveSessionNow(session)
                encounteredRecoverableFailure = true

            case .error(let error):
                if visibleSessionMessageID == session.messageID {
                    errorMessage = error.localizedDescription
                }
                saveSessionNow(session)
                encounteredRecoverableFailure = true
            }
        }

        guard isSessionActive(session), session.activeStreamID == streamID else { return }
        guard !finishedFromStream else { return }
        guard !Task.isCancelled else { return }

        session.isStreaming = false
        syncVisibleState(from: session)

        if FeatureFlags.useCloudflareGateway,
           !useDirectEndpoint,
           gatewayResumeTimedOut || !receivedAnyRecoveryEvent {
            #if DEBUG
            print("[Recovery] Gateway resume stalled for \(responseId); retrying direct")
            #endif
            await startStreamingRecovery(
                session: session,
                responseId: responseId,
                lastSeq: lastSeq,
                apiKey: apiKey,
                useDirectEndpoint: true
            )
            return
        }

        if encounteredRecoverableFailure || session.responseId != nil {
            await pollResponseUntilTerminal(session: session, responseId: responseId)
        }
    }

    private func pollResponseUntilTerminal(session: ResponseSession, responseId: String) async {
        guard !apiKey.isEmpty else { return }
        setRecoveryPhase(.pollingTerminal, for: session)

        let key = apiKey
        var attempts = 0
        let maxAttempts = 180
        var lastResult: OpenAIResponseFetchResult?
        var lastError: String?

        while !Task.isCancelled && attempts < maxAttempts {
            attempts += 1

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: key)
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
                    if let message = findMessage(byId: session.messageID) {
                        if result.status == .failed || result.status == .incomplete {
                            if visibleSessionMessageID == session.messageID {
                                errorMessage = result.errorMessage ?? "Response did not complete."
                            }
                        }
                        finishRecovery(
                            for: message,
                            session: session,
                            result: result,
                            fallbackText: recoveryFallbackText(for: message, session: session),
                            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
                        )
                    }
                    return
                }
            } catch {
                if let message = findMessage(byId: session.messageID),
                   handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: visibleSessionMessageID == session.messageID
                   ) {
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

        if let message = findMessage(byId: session.messageID) {
            if visibleSessionMessageID == session.messageID,
               let lastError,
               !lastError.isEmpty {
                errorMessage = lastError
            }
            finishRecovery(
                for: message,
                session: session,
                result: lastResult,
                fallbackText: recoveryFallbackText(for: message, session: session),
                fallbackThinking: recoveryFallbackThinking(for: message, session: session)
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

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }
            recoverSingleMessage(message: message, responseId: responseId, visible: false)
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

            guard let session = makeStreamingSession(for: newDraft) else {
                errorMessage = "Failed to restart orphaned draft."
                return
            }

            registerSession(session, visible: true)
            session.isStreaming = true
            session.isThinking = true
            setRecoveryPhase(.idle, for: session)
            syncVisibleState(from: session)
            errorMessage = nil

            #if DEBUG
            print("[Recovery] Starting resend stream for conversation: \(conversation.title), messages count: \(messages.count)")
            #endif

            startStreamingRequest(for: session)
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
                preferStreamingResume: activeMessage.usedBackgroundMode,
                visible: true
            )
        }

        for message in sortedMessages.dropLast() {
            guard let responseId = message.responseId else { continue }
            recoverSingleMessage(message: message, responseId: responseId, visible: false)
        }
    }

    private func recoverSingleMessage(message: Message, responseId: String, visible: Bool) {
        recoverResponse(
            messageId: message.id,
            responseId: responseId,
            preferStreamingResume: message.usedBackgroundMode,
            visible: visible
        )
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
            let session = currentVisibleSession,
            let draft = draftMessage,
            draft.usedBackgroundMode,
            draft.responseId != nil
        else {
            return false
        }

        saveSessionNow(session)
        errorMessage = nil
        detachVisibleSessionBinding()
        endBackgroundTask()

        #if DEBUG
        print("[Detach] Detached background response for \(reason)")
        #endif

        return true
    }

    // MARK: - Stop Generation

    func stopGeneration(savePartial: Bool = true) {
        guard let session = currentVisibleSession else { return }

        let pendingBackgroundCancellation: (responseId: String, messageId: UUID)? = {
            guard
                session.requestUsesBackgroundMode,
                let responseId = session.responseId
            else {
                return nil
            }

            return (responseId, session.messageID)
        }()

        session.activeStreamID = UUID()
        session.service.cancelStream()
        session.task?.cancel()
        errorMessage = nil

        if savePartial && !session.currentText.isEmpty {
            persistToolCallsAndCitations()
            finalizeSession(session)
        } else if let draft = findMessage(byId: session.messageID) {
            if !session.currentText.isEmpty {
                draft.content = session.currentText
            }
            if !session.currentThinking.isEmpty {
                draft.thinking = session.currentThinking
            }
            if !draft.content.isEmpty {
                draft.isComplete = true
                draft.lastSequenceNumber = nil
                try? modelContext.save()
                upsertMessage(draft)
                removeSession(session)
            } else {
                removeEmptyMessage(draft, for: session)
            }
        }

        setVisibleRecoveryPhase(.idle)
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
        if let session = currentVisibleSession {
            saveSessionNow(session)
        }

        detachVisibleSessionBinding()
        currentConversation = nil
        messages = []
        currentStreamingText = ""
        currentThinkingText = ""
        inputText = ""
        errorMessage = nil
        selectedImageData = nil
        pendingAttachments = []
        isThinking = false
        setVisibleRecoveryPhase(.idle)
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

        guard let session = makeStreamingSession(for: draft) else {
            errorMessage = "Failed to start response session."
            return
        }

        registerSession(session, visible: true)
        session.isStreaming = true
        session.isThinking = false
        syncVisibleState(from: session)

        HapticService.shared.impact(.medium)

        startStreamingRequest(for: session)
    }

    // MARK: - Load Conversation

    func loadConversation(_ conversation: Conversation) {
        if let session = currentVisibleSession {
            saveSessionNow(session)
        }

        detachVisibleSessionBinding()
        currentConversation = conversation
        messages = visibleMessages(for: conversation)

        applyConversationConfiguration(from: conversation)

        currentStreamingText = ""
        currentThinkingText = ""
        errorMessage = nil
        isThinking = false
        setVisibleRecoveryPhase(.idle)
        draftMessage = nil
        activeToolCalls = []
        liveCitations = []
        liveFilePathAnnotations = []
        lastSequenceNumber = nil
        activeRequestUsesBackgroundMode = false
        pendingAttachments = []
        filePreviewURL = nil
        fileDownloadError = nil

        refreshVisibleBindingForCurrentConversation()

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

    // MARK: - Session Management

    private func sessionRequestConfiguration(for conversation: Conversation?) -> (ModelType, ReasoningEffort, ServiceTier) {
        guard let conversation else {
            let effort = selectedModel.availableEfforts.contains(reasoningEffort) ? reasoningEffort : selectedModel.defaultEffort
            return (selectedModel, effort, serviceTier)
        }

        let model = ModelType(rawValue: conversation.model) ?? .gpt5_4
        let storedEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        let resolvedEffort = model.availableEfforts.contains(storedEffort) ? storedEffort : model.defaultEffort
        let resolvedTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard
        return (model, resolvedEffort, resolvedTier)
    }

    private func buildRequestMessages(for conversation: Conversation, excludingDraft draftID: UUID) -> [APIMessage] {
        conversation.messages
            .filter { $0.id != draftID && ($0.isComplete || $0.role == .user) }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map {
                APIMessage(
                    role: $0.role,
                    content: $0.content,
                    imageData: $0.imageData,
                    fileAttachments: $0.fileAttachments
                )
            }
    }

    private func makeStreamingSession(for draft: Message) -> ResponseSession? {
        guard let conversation = draft.conversation else { return nil }
        let requestMessages = buildRequestMessages(for: conversation, excludingDraft: draft.id)
        let configuration = sessionRequestConfiguration(for: conversation)

        return ResponseSession(
            message: draft,
            conversationID: conversation.id,
            requestMessages: requestMessages,
            requestModel: configuration.0,
            requestEffort: configuration.1,
            requestUsesBackgroundMode: conversation.backgroundModeEnabled,
            requestServiceTier: configuration.2
        )
    }

    private func makeRecoverySession(for message: Message) -> ResponseSession? {
        guard let conversation = message.conversation else { return nil }
        let configuration = sessionRequestConfiguration(for: conversation)

        return ResponseSession(
            message: message,
            conversationID: conversation.id,
            requestMessages: nil,
            requestModel: configuration.0,
            requestEffort: configuration.1,
            requestUsesBackgroundMode: message.usedBackgroundMode,
            requestServiceTier: configuration.2
        )
    }

    private func registerSession(_ session: ResponseSession, visible: Bool) {
        if let existing = activeResponseSessions[session.messageID], existing !== session {
            existing.task?.cancel()
            existing.service.cancelStream()
        }

        activeResponseSessions[session.messageID] = session

        if visible {
            bindVisibleSession(messageID: session.messageID)
        } else if visibleSessionMessageID == session.messageID {
            syncVisibleState(from: session)
        }
    }

    private func isSessionActive(_ session: ResponseSession) -> Bool {
        activeResponseSessions[session.messageID] === session
    }

    private func bindVisibleSession(messageID: UUID?) {
        visibleSessionMessageID = messageID

        guard
            let messageID,
            let session = activeResponseSessions[messageID],
            let message = findMessage(byId: messageID),
            currentConversation?.id == session.conversationID
        else {
            draftMessage = nil
            clearLiveGenerationState(clearDraft: false)
            return
        }

        draftMessage = message
        syncVisibleState(from: session)
        upsertMessage(message)
    }

    private func detachVisibleSessionBinding() {
        visibleSessionMessageID = nil
        draftMessage = nil
        clearLiveGenerationState(clearDraft: false)
        errorMessage = nil
    }

    private func setVisibleRecoveryPhase(_ phase: RecoveryPhase) {
        visibleRecoveryPhase = phase
        isRecovering = phase == .streamResuming
    }

    private func setRecoveryPhase(_ phase: RecoveryPhase, for session: ResponseSession) {
        session.recoveryPhase = phase
        if visibleSessionMessageID == session.messageID {
            setVisibleRecoveryPhase(phase)
        }
    }

    private func syncVisibleState(from session: ResponseSession) {
        guard visibleSessionMessageID == session.messageID else { return }

        currentStreamingText = session.currentText
        currentThinkingText = session.currentThinking
        activeToolCalls = session.toolCalls
        liveCitations = session.citations
        liveFilePathAnnotations = session.filePathAnnotations
        lastSequenceNumber = session.lastSequenceNumber
        activeRequestModel = session.requestModel
        activeRequestEffort = session.requestEffort
        activeRequestUsesBackgroundMode = session.requestUsesBackgroundMode
        activeRequestServiceTier = session.requestServiceTier
        isStreaming = session.isStreaming
        setVisibleRecoveryPhase(session.recoveryPhase)
        isThinking = session.isThinking

        if let message = findMessage(byId: session.messageID) {
            draftMessage = message
        }
    }

    private func saveSessionIfNeeded(_ session: ResponseSession) {
        let now = Date()
        let minimumInterval = session.requestUsesBackgroundMode ? 0.25 : 2.0
        guard now.timeIntervalSince(session.lastDraftSaveTime) >= minimumInterval else { return }
        saveSessionNow(session)
    }

    private func saveSessionNow(_ session: ResponseSession) {
        guard let message = findMessage(byId: session.messageID) else { return }

        message.content = session.currentText
        message.thinking = session.currentThinking.isEmpty ? nil : session.currentThinking
        message.toolCallsData = ToolCallInfo.encode(session.toolCalls)
        message.annotationsData = URLCitation.encode(session.citations)
        message.filePathAnnotationsData = FilePathAnnotation.encode(session.filePathAnnotations)
        message.lastSequenceNumber = session.lastSequenceNumber
        message.responseId = session.responseId
        message.usedBackgroundMode = session.requestUsesBackgroundMode
        message.conversation?.updatedAt = .now
        session.lastDraftSaveTime = Date()

        try? modelContext.save()

        if message.conversation?.id == currentConversation?.id {
            upsertMessage(message)
        }

        syncVisibleState(from: session)
    }

    private func finalizeSession(_ session: ResponseSession) {
        guard let message = findMessage(byId: session.messageID) else {
            removeSession(session)
            return
        }

        let finalText = session.currentText
        let finalThinking = session.currentThinking.isEmpty ? nil : session.currentThinking

        if finalText.isEmpty {
            removeEmptyMessage(message, for: session)
            return
        }

        message.content = finalText
        message.thinking = finalThinking
        message.toolCallsData = ToolCallInfo.encode(session.toolCalls)
        message.annotationsData = URLCitation.encode(session.citations)
        message.filePathAnnotationsData = FilePathAnnotation.encode(session.filePathAnnotations)
        message.isComplete = true
        message.lastSequenceNumber = nil
        message.responseId = session.responseId
        message.conversation?.updatedAt = .now
        upsertMessage(message)
        try? modelContext.save()

        let finishedConversation = message.conversation
        let wasVisible = visibleSessionMessageID == session.messageID

        removeSession(session)

        if let finishedConversation,
           finishedConversation.title == "New Chat",
           finishedConversation.messages.count >= 2 {
            Task { @MainActor in
                await self.generateTitleIfNeeded(for: finishedConversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }

    private func finalizeSessionAsPartial(_ session: ResponseSession) {
        guard let message = findMessage(byId: session.messageID) else {
            removeSession(session)
            return
        }

        let finalText = session.currentText.isEmpty ? message.content : session.currentText
        let finalThinking = session.currentThinking.isEmpty ? message.thinking : session.currentThinking

        message.content = finalText.isEmpty ? "[Response interrupted. Please try again.]" : finalText
        message.thinking = finalThinking
        message.toolCallsData = ToolCallInfo.encode(session.toolCalls)
        message.annotationsData = URLCitation.encode(session.citations)
        message.filePathAnnotationsData = FilePathAnnotation.encode(session.filePathAnnotations)
        message.isComplete = true
        message.lastSequenceNumber = nil
        message.responseId = session.responseId
        message.conversation?.updatedAt = .now
        upsertMessage(message)
        try? modelContext.save()

        removeSession(session)
    }

    private func removeEmptyMessage(_ message: Message, for session: ResponseSession) {
        if let conversation = message.conversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: idx)
        }

        modelContext.delete(message)
        try? modelContext.save()
        removeSession(session)
    }

    private func removeSession(_ session: ResponseSession) {
        session.task?.cancel()
        session.service.cancelStream()
        activeResponseSessions.removeValue(forKey: session.messageID)

        if visibleSessionMessageID == session.messageID {
            refreshVisibleBindingForCurrentConversation()
        }
    }

    private func refreshVisibleBindingForCurrentConversation() {
        guard let conversation = currentConversation else {
            detachVisibleSessionBinding()
            return
        }

        let activeMessages = conversation.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let message = activeMessages.last(where: { activeResponseSessions[$0.id] != nil }) {
            bindVisibleSession(messageID: message.id)
            return
        }

        if let message = activeMessages.last {
            visibleSessionMessageID = nil
            clearLiveGenerationState(clearDraft: false)
            draftMessage = message
        } else {
            detachVisibleSessionBinding()
        }
    }

    private func generateTitleIfNeeded(for conversation: Conversation) async {
        guard !apiKey.isEmpty else { return }
        guard conversation.title == "New Chat", conversation.messages.count >= 2 else { return }

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
        } catch {
            #if DEBUG
            print("[Title] Failed to generate title: \(error.localizedDescription)")
            #endif
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

    @discardableResult
    private func handleUnrecoverableRecoveryError(
        _ error: Error,
        for message: Message,
        responseId: String,
        session: ResponseSession,
        visible: Bool
    ) -> Bool {
        guard case let OpenAIServiceError.httpError(statusCode, responseBody) = error,
              statusCode == 404 else {
            return false
        }

        let fallbackText: String

        if message.usedBackgroundMode {
            if visible {
                errorMessage = "This response is no longer resumable."
            }
            fallbackText = recoveryFallbackText(for: message, session: session)
        } else {
            if visible {
                errorMessage = nil
            }
            fallbackText = interruptedResponseFallbackText(for: message, session: session)
        }

        #if DEBUG
        print("[Recovery] Response \(responseId) is no longer available: \(responseBody)")
        #endif

        finishRecovery(
            for: message,
            session: session,
            result: nil,
            fallbackText: fallbackText,
            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
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
        guard message.conversation?.id == currentConversation?.id else {
            return
        }

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
        setVisibleRecoveryPhase(.idle)
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

    private func suspendActiveSessionsForAppBackground() {
        let sessions = Array(activeResponseSessions.values)
        guard !sessions.isEmpty else { return }

        for session in sessions {
            saveSessionNow(session)
            session.activeStreamID = UUID()
            session.service.cancelStream()
            session.task?.cancel()
            session.isStreaming = false
            setRecoveryPhase(.idle, for: session)
            session.isThinking = false

            guard let message = findMessage(byId: session.messageID) else { continue }

            if session.responseId != nil {
                message.isComplete = false
                message.conversation?.updatedAt = .now
                upsertMessage(message)
            } else {
                message.content = interruptedResponseFallbackText(for: message, session: session)
                message.thinking = session.currentThinking.isEmpty ? nil : session.currentThinking
                message.isComplete = true
                message.lastSequenceNumber = nil
                message.conversation?.updatedAt = .now
                upsertMessage(message)
            }
        }

        try? modelContext.save()
        activeResponseSessions.removeAll()
        detachVisibleSessionBinding()
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
        session: ResponseSession,
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

        let conversation = message.conversation
        let wasVisible = visibleSessionMessageID == session.messageID
        removeSession(session)

        if let conversation {
            Task { @MainActor in
                await self.generateTitleIfNeeded(for: conversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }

    private func recoveryFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        if let session, !session.currentText.isEmpty {
            return session.currentText
        }

        if message.id == visibleSessionMessageID, !currentStreamingText.isEmpty {
            return currentStreamingText
        }

        return message.content
    }

    private func recoveryFallbackThinking(for message: Message, session: ResponseSession? = nil) -> String? {
        if let session, !session.currentThinking.isEmpty {
            return session.currentThinking
        }

        if message.id == visibleSessionMessageID, !currentThinkingText.isEmpty {
            return currentThinkingText
        }

        return message.thinking
    }

    private func interruptedResponseFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        let interruptionNotice = "Response interrupted because the app was closed before completion."
        let baseText = recoveryFallbackText(for: message, session: session)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseText.isEmpty else {
            return interruptionNotice
        }

        if baseText.contains(interruptionNotice) {
            return baseText
        }

        return "\(baseText)\n\n\(interruptionNotice)"
    }

    private func applyStreamEvent(_ event: StreamEvent, to session: ResponseSession, animated: Bool) -> StreamEventDisposition {
        let shouldAnimate = animated && visibleSessionMessageID == session.messageID

        switch event {
        case .responseCreated(let responseId):
            session.responseId = responseId
            if let draft = findMessage(byId: session.messageID) {
                draft.responseId = responseId
                draft.usedBackgroundMode = session.requestUsesBackgroundMode
                try? modelContext.save()
                upsertMessage(draft)
                #if DEBUG
                print("[VM] Saved responseId: \(responseId)")
                #endif
            }
            syncVisibleState(from: session)
            return .continued

        case .sequenceUpdate(let sequence):
            if let lastSequenceNumber = session.lastSequenceNumber {
                session.lastSequenceNumber = max(lastSequenceNumber, sequence)
            } else {
                session.lastSequenceNumber = sequence
            }
            saveSessionIfNeeded(session)
            return .continued

        case .textDelta(let delta):
            if session.isThinking {
                animateIfNeeded(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                    session.isThinking = false
                }
            }
            session.currentText += delta
            saveSessionIfNeeded(session)
            return .continued

        case .thinkingDelta(let delta):
            session.currentThinking += delta
            saveSessionIfNeeded(session)
            return .continued

        case .thinkingStarted:
            animateIfNeeded(shouldAnimate, animation: .easeIn(duration: 0.2)) {
                session.isThinking = true
            }
            syncVisibleState(from: session)
            return .continued

        case .thinkingFinished:
            animateIfNeeded(shouldAnimate, animation: .easeOut(duration: 0.2)) {
                session.isThinking = false
            }
            saveSessionNow(session)
            return .continued

        case .webSearchStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .webSearch, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .webSearchSearching(let callId):
            setToolCallStatus(in: session, callId, status: .searching, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .webSearchCompleted(let callId):
            setToolCallStatus(in: session, callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .codeInterpreter, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterInterpreting(let callId):
            setToolCallStatus(in: session, callId, status: .interpreting, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDelta(let callId, let codeDelta):
            appendToolCodeDelta(in: session, callId, delta: codeDelta)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCodeDone(let callId, let fullCode):
            setToolCode(in: session, callId, code: fullCode)
            saveSessionIfNeeded(session)
            return .continued

        case .codeInterpreterCompleted(let callId):
            setToolCallStatus(in: session, callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchStarted(let callId):
            startToolCallIfNeeded(in: session, id: callId, type: .fileSearch, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchSearching(let callId):
            setToolCallStatus(in: session, callId, status: .fileSearching, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .fileSearchCompleted(let callId):
            setToolCallStatus(in: session, callId, status: .completed, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .annotationAdded(let citation):
            addLiveCitationIfNeeded(in: session, citation, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .filePathAnnotationAdded(let annotation):
            addLiveFilePathAnnotationIfNeeded(in: session, annotation, animated: shouldAnimate)
            saveSessionIfNeeded(session)
            return .continued

        case .completed(let fullText, let fullThinking, let filePathAnns):
            if !fullText.isEmpty {
                session.currentText = fullText
            }
            if let fullThinking, !fullThinking.isEmpty {
                session.currentThinking = fullThinking
            }
            if let filePathAnns, !filePathAnns.isEmpty {
                session.filePathAnnotations = filePathAnns
            }
            saveSessionNow(session)
            return .terminalCompleted

        case .incomplete(let fullText, let fullThinking, let filePathAnns, let message):
            if !fullText.isEmpty {
                session.currentText = fullText
            }
            if let fullThinking, !fullThinking.isEmpty {
                session.currentThinking = fullThinking
            }
            if let filePathAnns, !filePathAnns.isEmpty {
                session.filePathAnnotations = filePathAnns
            }
            saveSessionNow(session)
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
                if let message = findMessage(byId: messageId),
                   let session = makeRecoverySession(for: message) {
                    registerSession(session, visible: false)
                    await pollResponseUntilTerminal(session: session, responseId: responseId)
                }

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

    private func startToolCallIfNeeded(in session: ResponseSession, id: String, type: ToolCallType, animated: Bool) {
        guard !session.toolCalls.contains(where: { $0.id == id }) else { return }

        let insert = {
            session.toolCalls.append(
                ToolCallInfo(
                    id: id,
                    type: type,
                    status: .inProgress
                )
            )
            self.syncVisibleState(from: session)
        }

        animateIfNeeded(animated, animation: .spring(duration: 0.3), insert)
    }

    private func setToolCallStatus(in session: ResponseSession, _ id: String, status: ToolCallStatus, animated: Bool) {
        guard let idx = session.toolCalls.firstIndex(where: { $0.id == id }) else { return }

        let update = {
            session.toolCalls[idx].status = status
            self.syncVisibleState(from: session)
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), update)
    }

    private func appendToolCodeDelta(in session: ResponseSession, _ id: String, delta: String) {
        guard let idx = session.toolCalls.firstIndex(where: { $0.id == id }) else { return }
        let existing = session.toolCalls[idx].code ?? ""
        session.toolCalls[idx].code = existing + delta
        syncVisibleState(from: session)
    }

    private func setToolCode(in session: ResponseSession, _ id: String, code: String) {
        guard let idx = session.toolCalls.firstIndex(where: { $0.id == id }) else { return }
        session.toolCalls[idx].code = code
        syncVisibleState(from: session)
    }

    private func addLiveCitationIfNeeded(in session: ResponseSession, _ citation: URLCitation, animated: Bool) {
        guard !session.citations.contains(where: { $0.id == citation.id }) else { return }

        let insert = {
            session.citations.append(citation)
            self.syncVisibleState(from: session)
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), insert)
    }

    private func addLiveFilePathAnnotationIfNeeded(in session: ResponseSession, _ annotation: FilePathAnnotation, animated: Bool) {
        guard !session.filePathAnnotations.contains(where: { $0.fileId == annotation.fileId }) else { return }

        let insert = {
            session.filePathAnnotations.append(annotation)
            self.syncVisibleState(from: session)
        }

        animateIfNeeded(animated, animation: .easeInOut(duration: 0.2), insert)
    }
}
