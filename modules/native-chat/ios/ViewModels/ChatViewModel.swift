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
    var inputText: String = ""
    var selectedModel: ModelType = .gpt5_4
    var reasoningEffort: ReasoningEffort = .medium
    var currentConversation: Conversation?
    var errorMessage: String?
    var showModelSelector: Bool = false
    var selectedImageData: Data?

    // Tool call state
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

    // Recovery task
    private var recoveryTask: Task<Void, Never>?

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        if let savedModel = UserDefaults.standard.string(forKey: "defaultModel"),
           let model = ModelType(rawValue: savedModel) {
            selectedModel = model
        }

        if let savedEffort = UserDefaults.standard.string(forKey: "defaultEffort"),
           let effort = ReasoningEffort(rawValue: savedEffort) {
            reasoningEffort = effort
        }

        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
        }

        setupLifecycleObservers()

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
            saveDraftNow()
            persistToolCallsAndCitations()

            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "StreamCompletion") { [weak self] in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.saveDraftNow()
                    self.persistToolCallsAndCitations()

                    self.activeStreamID = UUID()
                    self.openAIService.cancelStream()

                    if let draft = self.draftMessage {
                        if !self.currentStreamingText.isEmpty {
                            draft.content = self.currentStreamingText
                        }
                        if !self.currentThinkingText.isEmpty {
                            draft.thinking = self.currentThinkingText
                        }
                        if draft.content.isEmpty {
                            draft.content = "[Response interrupted. Please try again.]"
                            draft.thinking = nil
                        }
                        draft.isComplete = true
                        draft.conversation?.updatedAt = .now
                        self.upsertMessage(draft)
                        try? self.modelContext.save()
                    }

                    self.isStreaming = false
                    self.isThinking = false
                    self.activeToolCalls = []
                    self.liveCitations = []

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

        recoveryTask?.cancel()
        recoveryTask = nil

        if isStreaming {
            #if DEBUG
            print("[Foreground] Cancelling stale stream and switching to polling recovery if possible")
            #endif

            activeStreamID = UUID()
            openAIService.cancelStream()
            saveDraftNow()
            persistToolCallsAndCitations()
            isStreaming = false
            isThinking = false
        }

        if let draft = draftMessage {
            currentStreamingText = draft.content
            currentThinkingText = draft.thinking ?? ""

            if let responseId = draft.responseId {
                recoverResponse(messageId: draft.id, responseId: responseId)
                return
            }

            if !draft.content.isEmpty {
                finalizeDraftAsPartial()
                return
            }

            removeEmptyDraft()
        }

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
        let requestAPIKey = apiKey
        let requestModel = selectedModel
        let requestEffort = reasoningEffort

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
            var didReceiveCompletedEvent = false
            var pendingRecoveryResponseId: String?

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

                case .webSearchStarted(let callId):
                    withAnimation(.spring(duration: 0.3)) {
                        activeToolCalls.append(ToolCallInfo(
                            id: callId,
                            type: .webSearch,
                            status: .inProgress
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

                case .codeInterpreterStarted(let callId):
                    withAnimation(.spring(duration: 0.3)) {
                        activeToolCalls.append(ToolCallInfo(
                            id: callId,
                            type: .codeInterpreter,
                            status: .inProgress
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

                case .fileSearchStarted(let callId):
                    withAnimation(.spring(duration: 0.3)) {
                        activeToolCalls.append(ToolCallInfo(
                            id: callId,
                            type: .fileSearch,
                            status: .inProgress
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

                case .annotationAdded(let citation):
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if !liveCitations.contains(where: { $0.url == citation.url }) {
                            liveCitations.append(citation)
                        }
                    }

                case .completed(let fullText, let fullThinking):
                    didReceiveCompletedEvent = true

                    if !fullText.isEmpty {
                        currentStreamingText = fullText
                    }
                    if let thinking = fullThinking, !thinking.isEmpty {
                        currentThinkingText = thinking
                    }

                    persistToolCallsAndCitations()
                    finalizeDraft()

                case .connectionLost:
                    receivedConnectionLost = true
                    saveDraftNow()
                    persistToolCallsAndCitations()
                    #if DEBUG
                    print("[VM] Connection lost")
                    #endif

                case .error(let error):
                    saveDraftNow()
                    persistToolCallsAndCitations()

                    if let responseId = draftMessage?.responseId {
                        pendingRecoveryResponseId = responseId
                        #if DEBUG
                        print("[VM] Stream error, switching to polling recovery: \(error.localizedDescription)")
                        #endif
                    } else if !currentStreamingText.isEmpty {
                        finalizeDraftAsPartial()
                        errorMessage = error.localizedDescription
                        HapticService.shared.notify(.error)
                    } else {
                        removeEmptyDraft()
                        errorMessage = error.localizedDescription
                        isStreaming = false
                        isThinking = false
                        activeToolCalls = []
                        liveCitations = []
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
                isStreaming = false
                isThinking = false
                recoverResponse(messageId: draft.id, responseId: responseId)
                endBackgroundTask()
                return
            }

            if receivedConnectionLost {
                if let draft = draftMessage, let responseId = draft.responseId {
                    isStreaming = false
                    isThinking = false
                    recoverResponse(messageId: draft.id, responseId: responseId)
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
                    startStreamingRequest(reconnectAttempt: nextAttempt)
                    endBackgroundTask()
                    return
                }

                if !currentStreamingText.isEmpty {
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

            if isStreaming {
                if let draft = draftMessage, let responseId = draft.responseId {
                    saveDraftNow()
                    persistToolCallsAndCitations()
                    isStreaming = false
                    isThinking = false
                    recoverResponse(messageId: draft.id, responseId: responseId)
                } else if !currentStreamingText.isEmpty {
                    persistToolCallsAndCitations()
                    finalizeDraftAsPartial()
                } else {
                    removeEmptyDraft()
                    isStreaming = false
                    isThinking = false
                    activeToolCalls = []
                    liveCitations = []
                }
            }

            endBackgroundTask()
        }
    }

    // MARK: - Tool Call & Citation Persistence

    private func persistToolCallsAndCitations() {
        guard let draft = draftMessage else { return }

        if !activeToolCalls.isEmpty {
            draft.toolCallsData = ToolCallInfo.encode(activeToolCalls)
        }

        if !liveCitations.isEmpty {
            draft.annotationsData = URLCitation.encode(liveCitations)
        }

        try? modelContext.save()
    }

    // MARK: - Draft Persistence

    private func saveDraftIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastDraftSaveTime) >= 2.0 else { return }
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
        draft.conversation?.updatedAt = .now

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
        draft.conversation?.updatedAt = .now

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

    // MARK: - Polling Recovery

    private func recoverResponse(messageId: UUID, responseId: String) {
        guard !apiKey.isEmpty else {
            isRecovering = false
            return
        }

        recoveryTask?.cancel()
        errorMessage = nil
        isRecovering = true
        isStreaming = false
        isThinking = false

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
                self.isRecovering = false
                self.isStreaming = false
                self.isThinking = false
            }

            var attempts = 0
            let maxAttempts = 180
            var lastResult: OpenAIResponseFetchResult?
            var lastError: String?

            while !Task.isCancelled && attempts < maxAttempts {
                attempts += 1

                do {
                    let result = try await service.fetchResponse(responseId: respId, apiKey: key)
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
                        if let message = self.findMessage(byId: msgId) {
                            let fallbackText = !self.currentStreamingText.isEmpty ? self.currentStreamingText : message.content
                            let fallbackThinking = !self.currentThinkingText.isEmpty ? self.currentThinkingText : message.thinking
                            self.applyRecoveredResult(
                                result,
                                to: message,
                                fallbackText: fallbackText,
                                fallbackThinking: fallbackThinking
                            )
                            try? self.modelContext.save()
                            self.upsertMessage(message)
                        }

                        self.draftMessage = nil
                        self.clearLiveGenerationState(clearDraft: false)

                        if self.currentConversation?.title == "New Chat" && self.messages.count >= 2 {
                            await self.generateTitle()
                        }

                        HapticService.shared.notify(.success)

                        #if DEBUG
                        print("[Recovery] Recovered response \(respId) with status \(result.status.rawValue)")
                        #endif
                        return
                    }

                } catch {
                    lastError = error.localizedDescription
                    #if DEBUG
                    print("[Recovery] Poll error: \(lastError ?? "unknown"), attempt \(attempts)/\(maxAttempts)")
                    #endif

                    let delay: UInt64 = attempts < 10 ? 2_000_000_000 : 3_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }

            guard !Task.isCancelled else { return }

            if let message = self.findMessage(byId: msgId) {
                let fallbackText = !self.currentStreamingText.isEmpty ? self.currentStreamingText : message.content
                let fallbackThinking = !self.currentThinkingText.isEmpty ? self.currentThinkingText : message.thinking
                self.applyRecoveredResult(
                    lastResult,
                    to: message,
                    fallbackText: fallbackText,
                    fallbackThinking: fallbackThinking
                )
                try? self.modelContext.save()
                self.upsertMessage(message)
            }

            self.draftMessage = nil
            self.clearLiveGenerationState(clearDraft: false)

            #if DEBUG
            print("[Recovery] Finished with fallback after \(attempts) attempts. Last error: \(lastError ?? "none")")
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

    // MARK: - Stop Generation

    func stopGeneration(savePartial: Bool = true) {
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

    // MARK: - Helpers

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
        message.conversation?.updatedAt = .now
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
            // Non-critical
        }
    }
}
