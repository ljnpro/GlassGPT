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
    var isRecovering: Bool = false          // True when polling for a previously interrupted response
    var isRestoringConversation: Bool = false // True when loading previous conversation on app launch
    var inputText: String = ""
    var selectedModel: ModelType = .gpt5_4
    var reasoningEffort: ReasoningEffort = .medium
    var currentConversation: Conversation?
    var errorMessage: String?
    var showModelSelector: Bool = false
    var selectedImageData: Data?

    // Tool call state (live during streaming)
    var activeToolCalls: [ToolCallInfo] = []
    var liveCitations: [URLCitation] = []

    // File attachments pending send
    var pendingAttachments: [FileAttachment] = []

    // MARK: - Dependencies

    private let openAIService = OpenAIService()
    private let keychainService = KeychainService()
    private var modelContext: ModelContext

    // Stream invalidation token
    private var activeStreamID = UUID()

    // Draft message for real-time persistence during streaming
    private var draftMessage: Message?
    private var lastDraftSaveTime: Date = .distantPast

    // Background task
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // Recovery polling
    private var recoveryTask: Task<Void, Never>?

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Load defaults
        if let savedModel = UserDefaults.standard.string(forKey: "defaultModel"),
           let model = ModelType(rawValue: savedModel) {
            selectedModel = model
        }
        if let savedEffort = UserDefaults.standard.string(forKey: "defaultEffort"),
           let effort = ReasoningEffort(rawValue: savedEffort) {
            reasoningEffort = effort
        }

        // Ensure effort is valid for the loaded model
        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
        }

        // Listen for app lifecycle to handle background/foreground transitions
        setupLifecycleObservers()

        // On launch: restore last conversation and check for incomplete messages
        Task { @MainActor in
            await restoreLastConversation()
            await recoverIncompleteMessages()
            await resendOrphanedDrafts()
            await generateTitlesForUntitledConversations()
        }
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
            // Save current progress immediately
            saveDraftNow()
            persistToolCallsAndCitations()

            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "StreamCompletion") { [weak self] in
                // Background time expired — gracefully stop stream and prepare for recovery
                Task { @MainActor in
                    guard let self = self else { return }
                    self.saveDraftNow()
                    self.persistToolCallsAndCitations()

                    // Cancel the active stream so it doesn't produce errors in the background
                    self.activeStreamID = UUID()
                    self.openAIService.cancelStream()

                    // Finalize the draft as partial so it can be recovered later
                    if let draft = self.draftMessage, !draft.content.isEmpty {
                        self.finalizeDraftAsPartial()
                    }

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

    private func handleReturnToForeground() {
        endBackgroundTask()

        // Cancel any stale recovery tasks first
        recoveryTask?.cancel()
        recoveryTask = nil

        if !isStreaming, let draft = draftMessage {
            if !draft.content.isEmpty {
                finalizeDraftAsPartial()
            }
            if let responseId = draft.responseId {
                recoverResponse(messageId: draft.id, responseId: responseId)
                // recoverResponse handles isRecovering, so return early
                // to avoid double-recovery from recoverIncompleteMessagesInCurrentConversation
                return
            } else {
                // No responseId means we can't recover — clean up
                removeEmptyDraft()
            }
        }

        // Only run incomplete message recovery if we didn't already start recoverResponse above
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

    // MARK: - Document Handling

    /// Handle documents picked from the document picker.
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

    /// Remove a pending attachment.
    func removePendingAttachment(_ attachment: FileAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    /// Upload pending attachments to OpenAI and return file IDs.
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

        // Capture attachments before clearing
        let attachmentsToSend = pendingAttachments

        // Create user message
        let userMessage = Message(
            role: .user,
            content: text,
            imageData: selectedImageData
        )
        // Store file attachment metadata on the user message (for display)
        if !attachmentsToSend.isEmpty {
            userMessage.fileAttachmentsData = FileAttachment.encode(attachmentsToSend)
        }

        // Create or update conversation
        if currentConversation == nil {
            let conversation = Conversation(
                model: selectedModel.rawValue,
                reasoningEffort: reasoningEffort.rawValue
            )
            modelContext.insert(conversation)
            currentConversation = conversation
        }

        userMessage.conversation = currentConversation
        currentConversation?.messages.append(userMessage)
        currentConversation?.model = selectedModel.rawValue
        currentConversation?.reasoningEffort = reasoningEffort.rawValue
        currentConversation?.updatedAt = .now
        messages.append(userMessage)

        // Save user message immediately
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save your message."
            return
        }

        // Clear input
        inputText = ""
        selectedImageData = nil
        errorMessage = nil

        // Create draft assistant message
        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            isComplete: false
        )
        draft.conversation = currentConversation
        currentConversation?.messages.append(draft)
        try? modelContext.save()
        draftMessage = draft

        // Start streaming
        isStreaming = true
        isThinking = false
        currentStreamingText = ""
        currentThinkingText = ""
        activeToolCalls = []
        liveCitations = []

        HapticService.shared.impact(.light)

        // Upload files if needed, then start request
        if !attachmentsToSend.isEmpty {
            Task { @MainActor in
                let uploaded = await uploadPendingAttachments()
                // Update user message with uploaded file IDs
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
        let requestAPIKey = apiKey
        let requestModel = selectedModel
        let requestEffort = reasoningEffort
        // Build messages list (exclude the empty draft)
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
                reasoningEffort: requestEffort
            )

            var receivedConnectionLost = false

            for await event in stream {
                guard activeStreamID == streamID else { break }

                switch event {
                case .responseCreated(let responseId):
                    if let draft = draftMessage {
                        draft.responseId = responseId
                        try? modelContext.save()
                        #if DEBUG
                        print("[VM] Saved responseId: \(responseId)")
                        #endif
                    }

                case .textDelta(let delta):
                    if isThinking {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isThinking = false
                        }
                    }
                    currentStreamingText += delta
                    saveDraftIfNeeded()

                case .thinkingDelta(let delta):
                    currentThinkingText += delta
                    saveDraftIfNeeded()

                case .thinkingStarted:
                    withAnimation(.easeIn(duration: 0.2)) {
                        isThinking = true
                    }

                case .thinkingFinished:
                    withAnimation(.easeOut(duration: 0.2)) {
                        isThinking = false
                    }
                    saveDraftNow()

                // MARK: Web Search Events
                case .webSearchStarted(let callId):
                    withAnimation(.spring(duration: 0.3)) {
                        activeToolCalls.append(ToolCallInfo(
                            id: callId, type: .webSearch, status: .inProgress
                        ))
                    }

                case .webSearchSearching(let callId):
                    if let idx = activeToolCalls.firstIndex(where: { $0.id == callId }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeToolCalls[idx].status = .searching
                        }
                    }

                case .webSearchCompleted(let callId):
                    if let idx = activeToolCalls.firstIndex(where: { $0.id == callId }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeToolCalls[idx].status = .completed
                        }
                    }

                // MARK: Code Interpreter Events
                case .codeInterpreterStarted(let callId):
                    withAnimation(.spring(duration: 0.3)) {
                        activeToolCalls.append(ToolCallInfo(
                            id: callId, type: .codeInterpreter, status: .inProgress
                        ))
                    }

                case .codeInterpreterInterpreting(let callId):
                    if let idx = activeToolCalls.firstIndex(where: { $0.id == callId }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeToolCalls[idx].status = .interpreting
                        }
                    }

                case .codeInterpreterCodeDelta(let callId, let codeDelta):
                    if let idx = activeToolCalls.firstIndex(where: { $0.id == callId }) {
                        let existing = activeToolCalls[idx].code ?? ""
                        activeToolCalls[idx].code = existing + codeDelta
                    }

                case .codeInterpreterCodeDone(let callId, let fullCode):
                    if let idx = activeToolCalls.firstIndex(where: { $0.id == callId }) {
                        activeToolCalls[idx].code = fullCode
                    }

                case .codeInterpreterCompleted(let callId):
                    if let idx = activeToolCalls.firstIndex(where: { $0.id == callId }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeToolCalls[idx].status = .completed
                        }
                    }

                // MARK: File Search Events
                case .fileSearchStarted(let callId):
                    withAnimation(.spring(duration: 0.3)) {
                        activeToolCalls.append(ToolCallInfo(
                            id: callId, type: .fileSearch, status: .inProgress
                        ))
                    }

                case .fileSearchSearching(let callId):
                    if let idx = activeToolCalls.firstIndex(where: { $0.id == callId }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeToolCalls[idx].status = .fileSearching
                        }
                    }

                case .fileSearchCompleted(let callId):
                    if let idx = activeToolCalls.firstIndex(where: { $0.id == callId }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeToolCalls[idx].status = .completed
                        }
                    }

                // MARK: Annotation Events
                case .annotationAdded(let citation):
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // Deduplicate by URL
                        if !liveCitations.contains(where: { $0.url == citation.url }) {
                            liveCitations.append(citation)
                        }
                    }

                case .completed(let fullText, let fullThinking):
                    if !fullText.isEmpty && fullText.count > currentStreamingText.count {
                        currentStreamingText = fullText
                    }
                    if let thinking = fullThinking, !thinking.isEmpty,
                       thinking.count > currentThinkingText.count {
                        currentThinkingText = thinking
                    }
                    // Persist tool calls and citations on the draft
                    persistToolCallsAndCitations()
                    finalizeDraft()

                case .connectionLost:
                    receivedConnectionLost = true
                    saveDraftNow()
                    #if DEBUG
                    print("[VM] Connection lost (attempt \(reconnectAttempt + 1)/\(Self.maxReconnectAttempts))")
                    #endif

                case .error(let error):
                    if !currentStreamingText.isEmpty {
                        persistToolCallsAndCitations()
                        finalizeDraftAsPartial()
                        if let draft = draftMessage, let responseId = draft.responseId {
                            recoverResponse(messageId: draft.id, responseId: responseId)
                        }
                    } else {
                        removeEmptyDraft()
                    }
                    errorMessage = error.localizedDescription
                    isStreaming = false
                    isThinking = false
                    activeToolCalls = []
                    liveCitations = []
                    HapticService.shared.notify(.error)
                }
            }

            // Handle auto-reconnect on connection loss
            if receivedConnectionLost && activeStreamID == streamID {
                let nextAttempt = reconnectAttempt + 1

                if nextAttempt < Self.maxReconnectAttempts {
                    if let draft = draftMessage, let responseId = draft.responseId {
                        do {
                            let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: requestAPIKey)
                            if !result.text.isEmpty {
                                currentStreamingText = result.text
                            }
                            if let thinking = result.thinking, !thinking.isEmpty {
                                currentThinkingText = thinking
                            }
                            // Merge recovered tool calls and citations into live state
                            for tc in result.toolCalls {
                                if !activeToolCalls.contains(where: { $0.id == tc.id }) {
                                    activeToolCalls.append(tc)
                                }
                            }
                            for cit in result.annotations {
                                if !liveCitations.contains(where: { $0.url == cit.url && $0.startIndex == cit.startIndex }) {
                                    liveCitations.append(cit)
                                }
                            }
                            persistToolCallsAndCitations()
                            finalizeDraft()
                            endBackgroundTask()
                            return
                        } catch {
                            let errorMsg = error.localizedDescription
                            if errorMsg.contains("__IN_PROGRESS__") {
                                let delay = Self.reconnectBaseDelay * UInt64(1 << reconnectAttempt)
                                #if DEBUG
                                print("[VM] Reconnecting in \(Double(delay) / 1_000_000_000)s (server still in progress)")
                                #endif
                                try? await Task.sleep(nanoseconds: delay)

                                guard activeStreamID == streamID else {
                                    endBackgroundTask()
                                    return
                                }

                                recoverResponse(messageId: draft.id, responseId: responseId)
                                endBackgroundTask()
                                return
                            }
                        }
                    }

                    let delay = Self.reconnectBaseDelay * UInt64(1 << reconnectAttempt)
                    #if DEBUG
                    print("[VM] Reconnecting in \(Double(delay) / 1_000_000_000)s (no responseId, full retry)")
                    #endif
                    try? await Task.sleep(nanoseconds: delay)

                    guard activeStreamID == streamID else {
                        endBackgroundTask()
                        return
                    }

                    HapticService.shared.impact(.light)
                    startStreamingRequest(reconnectAttempt: nextAttempt)
                    return
                } else {
                    #if DEBUG
                    print("[VM] Max reconnect attempts exhausted")
                    #endif
                    if let draft = draftMessage, let responseId = draft.responseId {
                        persistToolCallsAndCitations()
                        finalizeDraftAsPartial()
                        recoverResponse(messageId: draft.id, responseId: responseId)
                    } else if !currentStreamingText.isEmpty {
                        persistToolCallsAndCitations()
                        finalizeDraftAsPartial()
                    } else {
                        removeEmptyDraft()
                        errorMessage = "Connection lost. Please check your network and try again."
                        isStreaming = false
                        isThinking = false
                        activeToolCalls = []
                        liveCitations = []
                        HapticService.shared.notify(.error)
                    }
                    endBackgroundTask()
                    return
                }
            }

            // Stream ended without explicit completed event
            if activeStreamID == streamID && isStreaming {
                if !currentStreamingText.isEmpty {
                    persistToolCallsAndCitations()
                    finalizeDraftAsPartial()
                    if let draft = draftMessage, let responseId = draft.responseId {
                        recoverResponse(messageId: draft.id, responseId: responseId)
                    }
                } else {
                    if let draft = draftMessage, let responseId = draft.responseId {
                        isStreaming = false
                        isThinking = false
                        activeToolCalls = []
                        liveCitations = []
                        recoverResponse(messageId: draft.id, responseId: responseId)
                    } else {
                        removeEmptyDraft()
                        isStreaming = false
                        isThinking = false
                        activeToolCalls = []
                        liveCitations = []
                    }
                }
            }

            endBackgroundTask()
        }
    }

    // MARK: - Tool Call & Citation Persistence

    /// Save active tool calls and live citations to the draft message before finalization.
    private func persistToolCallsAndCitations() {
        guard let draft = draftMessage else { return }

        // Save all tool calls (including in-progress ones for history)
        if !activeToolCalls.isEmpty {
            draft.toolCallsData = ToolCallInfo.encode(activeToolCalls)
        }

        // Save citations
        if !liveCitations.isEmpty {
            draft.annotationsData = URLCitation.encode(liveCitations)
        }

        try? modelContext.save()
    }

    // MARK: - Draft Persistence

    private func saveDraftIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastDraftSaveTime) >= 1.0 else { return }
        saveDraftNow()
    }

    private func saveDraftNow() {
        guard let draft = draftMessage else { return }
        draft.content = currentStreamingText
        draft.thinking = currentThinkingText.isEmpty ? nil : currentThinkingText
        lastDraftSaveTime = Date()
        try? modelContext.save()
    }

    private func finalizeDraft() {
        guard !currentStreamingText.isEmpty else {
            removeEmptyDraft()
            isStreaming = false
            isThinking = false
            activeToolCalls = []
            liveCitations = []
            return
        }

        let finalText = currentStreamingText
        let finalThinking = currentThinkingText.isEmpty ? nil : currentThinkingText

        if let draft = draftMessage {
            draft.content = finalText
            draft.thinking = finalThinking
            draft.isComplete = true
            currentConversation?.updatedAt = .now

            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
            isThinking = false
            isRecovering = false
            activeToolCalls = []
            liveCitations = []

            if !messages.contains(where: { $0.id == draft.id }) {
                messages.append(draft)
            }

            try? modelContext.save()
            draftMessage = nil
        } else {
            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
            isThinking = false
            isRecovering = false
            activeToolCalls = []
            liveCitations = []
        }

        if currentConversation?.title == "New Chat" && messages.count >= 2 {
            Task { @MainActor in
                await generateTitle()
            }
        }

        HapticService.shared.notify(.success)
    }

    private func finalizeDraftAsPartial() {
        guard let draft = draftMessage else { return }

        draft.content = currentStreamingText
        draft.thinking = currentThinkingText.isEmpty ? nil : currentThinkingText
        currentConversation?.updatedAt = .now

        currentStreamingText = ""
        currentThinkingText = ""
        isStreaming = false
        isThinking = false
        isRecovering = false
        activeToolCalls = []
        liveCitations = []

        if !messages.contains(where: { $0.id == draft.id }) {
            messages.append(draft)
        }

        try? modelContext.save()
    }

    private func removeEmptyDraft() {
        guard let draft = draftMessage else { return }
        if let conversation = currentConversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
            conversation.messages.remove(at: idx)
        }
        modelContext.delete(draft)
        try? modelContext.save()
        draftMessage = nil
    }

    // MARK: - Response Recovery (Polling)

    private func recoverResponse(messageId: UUID, responseId: String) {
        guard !apiKey.isEmpty else {
            isRecovering = false
            return
        }

        recoveryTask?.cancel()
        isRecovering = true

        let key = apiKey
        let service = openAIService
        let msgId = messageId
        let respId = responseId

        recoveryTask = Task { @MainActor in
            // Use defer to guarantee isRecovering is always reset, even on cancellation
            defer {
                self.isRecovering = false
            }

            var attempts = 0
            let maxAttempts = 60  // ~2 minutes max (60 * 2s)
            var lastError: String?

            while !Task.isCancelled && attempts < maxAttempts {
                attempts += 1

                do {
                    let result = try await service.fetchResponse(responseId: respId, apiKey: key)

                    if let message = self.findMessage(byId: msgId) {
                        if !result.text.isEmpty {
                            message.content = result.text
                        }
                        if let thinking = result.thinking, !thinking.isEmpty {
                            message.thinking = thinking
                        }
                        // Save tool calls and citations from recovery
                        if !result.toolCalls.isEmpty {
                            message.toolCallsData = ToolCallInfo.encode(result.toolCalls)
                        }
                        if !result.annotations.isEmpty {
                            message.annotationsData = URLCitation.encode(result.annotations)
                        }
                        message.isComplete = true
                        try? self.modelContext.save()

                        if let idx = self.messages.firstIndex(where: { $0.id == msgId }) {
                            self.messages[idx] = message
                        }

                        #if DEBUG
                        print("[Recovery] Successfully recovered response \(respId) (\(result.text.count) chars)")
                        #endif
                    }

                    self.draftMessage = nil

                    if self.currentConversation?.title == "New Chat" && self.messages.count >= 2 {
                        await self.generateTitle()
                    }

                    HapticService.shared.notify(.success)
                    return

                } catch {
                    let errorMsg = error.localizedDescription
                    if errorMsg.contains("__IN_PROGRESS__") {
                        #if DEBUG
                        if attempts <= 3 || attempts % 10 == 0 {
                            print("[Recovery] Response still in progress, attempt \(attempts)/\(maxAttempts)")
                        }
                        #endif
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    } else {
                        lastError = errorMsg
                        #if DEBUG
                        print("[Recovery] Error: \(errorMsg), attempt \(attempts)")
                        #endif
                        if attempts < 5 {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            continue
                        } else {
                            break
                        }
                    }
                }
            }

            self.draftMessage = nil

            if let message = self.findMessage(byId: msgId) {
                message.isComplete = true
                if message.content.isEmpty {
                    message.content = "[Response interrupted. Please try again.]"
                }
                try? self.modelContext.save()

                // Refresh the messages array so UI updates
                if let idx = self.messages.firstIndex(where: { $0.id == msgId }) {
                    self.messages[idx] = message
                }
            }

            #if DEBUG
            let errorDesc = lastError ?? "timeout"
            print("[Recovery] Failed after \(attempts) attempts. Last error: \(errorDesc)")
            #endif
        }
    }

    private func recoverIncompleteMessages() async {
        guard !apiKey.isEmpty else { return }

        await cleanupStaleDrafts()

        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId != nil
            }
        )

        guard let incompleteMessages = try? modelContext.fetch(descriptor) else { return }
        guard !incompleteMessages.isEmpty else { return }

        #if DEBUG
        print("[Recovery] Found \(incompleteMessages.count) incomplete message(s) to recover")
        #endif

        isRecovering = true
        defer { isRecovering = false }

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }

            #if DEBUG
            print("[Recovery] Recovering message \(message.id) with responseId \(responseId)")
            #endif

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

        for draft in draftsToResend {
            guard let conversation = draft.conversation else {
                modelContext.delete(draft)
                try? modelContext.save()
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
            messages = conversation.messages
                .sorted { $0.createdAt < $1.createdAt }
                .filter { $0.id != draft.id }
            selectedModel = ModelType(rawValue: conversation.model) ?? .gpt5_4
            reasoningEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high

            if !selectedModel.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = selectedModel.defaultEffort
            }

            if let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
                conversation.messages.remove(at: idx)
            }
            modelContext.delete(draft)
            try? modelContext.save()

            let newDraft = Message(
                role: .assistant,
                content: "",
                thinking: nil,
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

        isRecovering = true
        defer { isRecovering = false }

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }
            await recoverSingleMessage(message: message, responseId: responseId)
        }
    }

    private func recoverSingleMessage(message: Message, responseId: String) async {
        let key = apiKey
        var attempts = 0
        let maxAttempts = 60  // ~2 minutes max

        while attempts < maxAttempts {
            attempts += 1

            do {
                let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: key)

                if !result.text.isEmpty {
                    message.content = result.text
                }
                if let thinking = result.thinking, !thinking.isEmpty {
                    message.thinking = thinking
                }
                // Save tool calls and citations from recovery
                if !result.toolCalls.isEmpty {
                    message.toolCallsData = ToolCallInfo.encode(result.toolCalls)
                }
                if !result.annotations.isEmpty {
                    message.annotationsData = URLCitation.encode(result.annotations)
                }
                message.isComplete = true
                try? modelContext.save()

                if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[idx] = message
                }

                #if DEBUG
                print("[Recovery] Recovered message \(message.id) (\(result.text.count) chars)")
                #endif
                return

            } catch {
                let errorMsg = error.localizedDescription
                if errorMsg.contains("__IN_PROGRESS__") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                } else if attempts < 5 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                } else {
                    break
                }
            }
        }

        message.isComplete = true
        if message.content.isEmpty {
            message.content = "[Response interrupted. Please try again.]"
        }
        try? modelContext.save()
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

    // MARK: - Stop Generation

    func stopGeneration(savePartial: Bool = true) {
        activeStreamID = UUID()
        openAIService.cancelStream()
        recoveryTask?.cancel()
        errorMessage = nil

        if savePartial && !currentStreamingText.isEmpty {
            persistToolCallsAndCitations()
            finalizeDraft()
        } else if let draft = draftMessage, !draft.content.isEmpty {
            draft.isComplete = true
            try? modelContext.save()
            if !messages.contains(where: { $0.id == draft.id }) {
                messages.append(draft)
            }
            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
            isThinking = false
            activeToolCalls = []
            liveCitations = []
            draftMessage = nil
        } else {
            removeEmptyDraft()
            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
            isThinking = false
            activeToolCalls = []
            liveCitations = []
        }

        isRecovering = false
        endBackgroundTask()
        HapticService.shared.impact(.medium)
    }

    // MARK: - New Chat

    func startNewChat() {
        if isStreaming {
            stopGeneration(savePartial: true)
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

        HapticService.shared.impact(.medium)

        startStreamingRequest()
    }

    // MARK: - Load Conversation

    func loadConversation(_ conversation: Conversation) {
        if isStreaming {
            stopGeneration(savePartial: true)
        }
        recoveryTask?.cancel()

        currentConversation = conversation
        messages = conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .filter { !($0.role == .assistant && $0.content.isEmpty && !$0.isComplete) }
        selectedModel = ModelType(rawValue: conversation.model) ?? .gpt5_4
        reasoningEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high

        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
        }

        currentStreamingText = ""
        currentThinkingText = ""
        errorMessage = nil
        isThinking = false
        isRecovering = false
        draftMessage = nil
        activeToolCalls = []
        liveCitations = []
        pendingAttachments = []

        Task { @MainActor in
            await recoverIncompleteMessagesInCurrentConversation()
        }
    }

    // MARK: - Restore Last Conversation

    private func restoreLastConversation() async {
        isRestoringConversation = true

        var descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let conversations = try? modelContext.fetch(descriptor),
           let lastConversation = conversations.first,
           !lastConversation.messages.isEmpty {
            currentConversation = lastConversation
            messages = lastConversation.messages
                .sorted { $0.createdAt < $1.createdAt }
                .filter { !($0.role == .assistant && $0.content.isEmpty && !$0.isComplete) }
            selectedModel = ModelType(rawValue: lastConversation.model) ?? .gpt5_4
            reasoningEffort = ReasoningEffort(rawValue: lastConversation.reasoningEffort) ?? .high

            if !selectedModel.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = selectedModel.defaultEffort
            }

            #if DEBUG
            print("[Restore] Loaded last conversation: \(lastConversation.title) (\(messages.count) messages)")
            #endif
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        isRestoringConversation = false
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

    // MARK: - Private

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
            // Title generation failure is non-critical
        }
    }
}
