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
        // Save current draft immediately when going to background
        if isStreaming {
            saveDraftNow()

            // Request background execution time
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "StreamCompletion") { [weak self] in
                // System is about to kill the background task — save what we have
                Task { @MainActor in
                    self?.saveDraftNow()
                    self?.endBackgroundTask()
                }
            }
        }

        // Generate title before app exits if it's still "New Chat"
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

        // If we were streaming but the connection died while in background
        if !isStreaming, let draft = draftMessage {
            // Stream ended while in background
            if !draft.content.isEmpty {
                // We have partial content — finalize what we have, then try recovery
                finalizeDraftAsPartial()
            }
            // Try to recover the full response via polling
            if let responseId = draft.responseId {
                recoverResponse(messageId: draft.id, responseId: responseId)
            }
        }

        // Also check for any other incomplete messages in the current conversation
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

    // MARK: - Send Message

    func sendMessage() {
        guard !isStreaming else { return }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Please add your OpenAI API key in Settings."
            return
        }

        // Create user message
        let userMessage = Message(
            role: .user,
            content: text,
            imageData: selectedImageData
        )

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

        // Create draft assistant message immediately with isComplete = false.
        // This ensures that even if the app is killed mid-stream,
        // the partial response is already in the database and can be recovered.
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

        HapticService.shared.impact(.light)

        startStreamingRequest()
    }

    // MARK: - Core Streaming Logic

    // Auto-reconnect constants
    private static let maxReconnectAttempts = 3
    private static let reconnectBaseDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds

    private func startStreamingRequest(reconnectAttempt: Int = 0) {
        let requestAPIKey = apiKey
        let requestModel = selectedModel
        let requestEffort = reasoningEffort
        // Build messages list (exclude the empty draft)
        let requestMessages = messages
            .filter { $0.isComplete || $0.role == .user }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map {
                APIMessage(role: $0.role, content: $0.content, imageData: $0.imageData)
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
                    // Save the response ID immediately for recovery
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
                    // Periodically save draft (every ~1 second)
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
                    // Save thinking content immediately when thinking finishes
                    saveDraftNow()

                case .completed(let fullText, let fullThinking):
                    if !fullText.isEmpty && fullText.count > currentStreamingText.count {
                        currentStreamingText = fullText
                    }
                    if let thinking = fullThinking, !thinking.isEmpty,
                       thinking.count > currentThinkingText.count {
                        currentThinkingText = thinking
                    }
                    finalizeDraft()

                case .connectionLost:
                    receivedConnectionLost = true
                    // Save current progress immediately
                    saveDraftNow()
                    #if DEBUG
                    print("[VM] Connection lost (attempt \(reconnectAttempt + 1)/\(Self.maxReconnectAttempts))")
                    #endif

                case .error(let error):
                    if !currentStreamingText.isEmpty {
                        // We have partial content — save it, then try recovery
                        finalizeDraftAsPartial()
                        // Attempt recovery if we have a response ID
                        if let draft = draftMessage, let responseId = draft.responseId {
                            recoverResponse(messageId: draft.id, responseId: responseId)
                        }
                    } else {
                        removeEmptyDraft()
                    }
                    errorMessage = error.localizedDescription
                    isStreaming = false
                    isThinking = false
                    HapticService.shared.notify(.error)
                }
            }

            // Handle auto-reconnect on connection loss
            if receivedConnectionLost && activeStreamID == streamID {
                let nextAttempt = reconnectAttempt + 1

                if nextAttempt < Self.maxReconnectAttempts {
                    // First, check if the server already completed the response
                    if let draft = draftMessage, let responseId = draft.responseId {
                        do {
                            let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: requestAPIKey)
                            // Server completed! Use the full response.
                            if !result.text.isEmpty {
                                currentStreamingText = result.text
                            }
                            if let thinking = result.thinking, !thinking.isEmpty {
                                currentThinkingText = thinking
                            }
                            finalizeDraft()
                            endBackgroundTask()
                            return
                        } catch {
                            let errorMsg = error.localizedDescription
                            if errorMsg.contains("__IN_PROGRESS__") {
                                // Server is still generating — reconnect with exponential backoff
                                let delay = Self.reconnectBaseDelay * UInt64(1 << reconnectAttempt) // 1s, 2s, 4s
                                #if DEBUG
                                print("[VM] Reconnecting in \(Double(delay) / 1_000_000_000)s (server still in progress)")
                                #endif
                                try? await Task.sleep(nanoseconds: delay)

                                guard activeStreamID == streamID else {
                                    endBackgroundTask()
                                    return
                                }

                                // Switch to polling-based recovery since we already have a responseId
                                // (re-establishing SSE won't resume the same response)
                                recoverResponse(messageId: draft.id, responseId: responseId)
                                endBackgroundTask()
                                return
                            }
                            // Other error — fall through to retry via new stream
                        }
                    }

                    // No responseId yet — retry the full request with exponential backoff
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
                    // Max retries exhausted — fall through to recovery or error
                    #if DEBUG
                    print("[VM] Max reconnect attempts exhausted")
                    #endif
                    if let draft = draftMessage, let responseId = draft.responseId {
                        finalizeDraftAsPartial()
                        recoverResponse(messageId: draft.id, responseId: responseId)
                    } else if !currentStreamingText.isEmpty {
                        finalizeDraftAsPartial()
                    } else {
                        removeEmptyDraft()
                        errorMessage = "Connection lost. Please check your network and try again."
                        isStreaming = false
                        isThinking = false
                        HapticService.shared.notify(.error)
                    }
                    endBackgroundTask()
                    return
                }
            }

            // Stream ended without explicit completed event — save what we have
            if activeStreamID == streamID && isStreaming {
                if !currentStreamingText.isEmpty {
                    finalizeDraftAsPartial()
                    // Try recovery
                    if let draft = draftMessage, let responseId = draft.responseId {
                        recoverResponse(messageId: draft.id, responseId: responseId)
                    }
                } else {
                    // No content at all — try recovery if we have responseId
                    if let draft = draftMessage, let responseId = draft.responseId {
                        // Keep the draft, start recovery
                        isStreaming = false
                        isThinking = false
                        recoverResponse(messageId: draft.id, responseId: responseId)
                    } else {
                        removeEmptyDraft()
                        isStreaming = false
                        isThinking = false
                    }
                }
            }

            endBackgroundTask()
        }
    }

    // MARK: - Draft Persistence

    /// Save draft to database if enough time has passed since last save (~1 second).
    private func saveDraftIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastDraftSaveTime) >= 1.0 else { return }
        saveDraftNow()
    }

    /// Immediately persist the current streaming content to the draft message.
    private func saveDraftNow() {
        guard let draft = draftMessage else { return }
        draft.content = currentStreamingText
        draft.thinking = currentThinkingText.isEmpty ? nil : currentThinkingText
        lastDraftSaveTime = Date()
        try? modelContext.save()
    }

    /// Finalize the draft as a complete message.
    private func finalizeDraft() {
        guard !currentStreamingText.isEmpty else {
            removeEmptyDraft()
            isStreaming = false
            isThinking = false
            return
        }

        let finalText = currentStreamingText
        let finalThinking = currentThinkingText.isEmpty ? nil : currentThinkingText

        if let draft = draftMessage {
            draft.content = finalText
            draft.thinking = finalThinking
            draft.isComplete = true
            currentConversation?.updatedAt = .now

            // Hide streaming bubble FIRST to prevent visual duplication
            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
            isThinking = false

            // Add to messages array for display (draft is already in SwiftData)
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
        }

        // Generate title for new conversations
        if currentConversation?.title == "New Chat" && messages.count >= 2 {
            Task { @MainActor in
                await generateTitle()
            }
        }

        HapticService.shared.notify(.success)
    }

    /// Finalize the draft as a partial (incomplete) message.
    /// The content is saved but isComplete remains false so recovery can update it later.
    private func finalizeDraftAsPartial() {
        guard let draft = draftMessage else { return }

        draft.content = currentStreamingText
        draft.thinking = currentThinkingText.isEmpty ? nil : currentThinkingText
        // isComplete stays false — recovery will set it to true
        currentConversation?.updatedAt = .now

        currentStreamingText = ""
        currentThinkingText = ""
        isStreaming = false
        isThinking = false

        // Add to messages array for display
        if !messages.contains(where: { $0.id == draft.id }) {
            messages.append(draft)
        }

        try? modelContext.save()
        // Don't nil out draftMessage yet — recovery might need it
    }

    /// Remove an empty draft message (when streaming failed before producing any content).
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

    /// Recover a specific response by polling the OpenAI API.
    /// This is called when:
    /// - App returns to foreground after streaming was interrupted
    /// - App launches and finds incomplete messages from a previous session
    /// - Stream errors out but we have a response_id
    private func recoverResponse(messageId: UUID, responseId: String) {
        guard !apiKey.isEmpty else { return }

        // Cancel any existing recovery task
        recoveryTask?.cancel()

        isRecovering = true

        let key = apiKey
        let service = openAIService
        let msgId = messageId
        let respId = responseId

        recoveryTask = Task { @MainActor in
            var attempts = 0
            let maxAttempts = 150  // 150 * 2s = 5 minutes max wait
            var lastError: String?

            while !Task.isCancelled && attempts < maxAttempts {
                attempts += 1

                do {
                    let result = try await service.fetchResponse(responseId: respId, apiKey: key)

                    // Success! Update the message
                    if let message = self.findMessage(byId: msgId) {
                        if !result.text.isEmpty {
                            message.content = result.text
                        }
                        if let thinking = result.thinking, !thinking.isEmpty {
                            message.thinking = thinking
                        }
                        message.isComplete = true
                        try? self.modelContext.save()

                        // Update the displayed messages array
                        if let idx = self.messages.firstIndex(where: { $0.id == msgId }) {
                            // Force UI refresh
                            self.messages[idx] = message
                        }

                        #if DEBUG
                        print("[Recovery] Successfully recovered response \(respId) (\(result.text.count) chars)")
                        #endif
                    }

                    self.isRecovering = false
                    self.draftMessage = nil

                    // Generate title if needed
                    if self.currentConversation?.title == "New Chat" && self.messages.count >= 2 {
                        await self.generateTitle()
                    }

                    HapticService.shared.notify(.success)
                    return

                } catch {
                    let errorMsg = error.localizedDescription
                    if errorMsg.contains("__IN_PROGRESS__") {
                        // Response is still being generated — wait and retry
                        #if DEBUG
                        if attempts <= 3 || attempts % 10 == 0 {
                            print("[Recovery] Response still in progress, attempt \(attempts)/\(maxAttempts)")
                        }
                        #endif
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        continue
                    } else {
                        lastError = errorMsg
                        #if DEBUG
                        print("[Recovery] Error: \(errorMsg), attempt \(attempts)")
                        #endif
                        // For non-in-progress errors, retry a few times with backoff
                        if attempts < 5 {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            continue
                        } else {
                            break
                        }
                    }
                }
            }

            // Recovery failed or timed out
            self.isRecovering = false
            self.draftMessage = nil

            // Mark the message as complete even if recovery failed
            // (so we don't keep trying forever)
            if let message = self.findMessage(byId: msgId) {
                message.isComplete = true
                if message.content.isEmpty {
                    message.content = "[Response interrupted. Please try again.]"
                }
                try? self.modelContext.save()
            }

            #if DEBUG
            print("[Recovery] Failed after \(attempts) attempts. Last error: \(lastError ?? "timeout")")
            #endif
        }
    }

    /// Check all conversations for incomplete messages and recover them.
    /// Called on app launch.
    private func recoverIncompleteMessages() async {
        guard !apiKey.isEmpty else { return }

        // First, clean up stale drafts (older than 24 hours)
        // These are messages from sessions that were interrupted long ago
        // and whose server-side responses have likely expired.
        await cleanupStaleDrafts()

        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId != nil
            }
        )

        guard let incompleteMessages = try? modelContext.fetch(descriptor) else { return }

        #if DEBUG
        if !incompleteMessages.isEmpty {
            print("[Recovery] Found \(incompleteMessages.count) incomplete message(s) to recover")
        }
        #endif

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }

            #if DEBUG
            print("[Recovery] Recovering message \(message.id) with responseId \(responseId)")
            #endif

            // Recover each one (sequentially to avoid overwhelming the API)
            await recoverSingleMessage(message: message, responseId: responseId)
        }
    }

    /// Clean up stale draft messages that are older than 24 hours.
    /// These are messages from interrupted sessions whose server-side responses
    /// have likely expired and cannot be recovered.
    private func cleanupStaleDrafts() async {
        let staleThreshold = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago

        // Fetch all incomplete messages (with or without responseId)
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
                // Empty draft with no responseId — just delete it
                modelContext.delete(message)
                cleanedCount += 1
            } else {
                // Has content or responseId but is stale — mark as complete
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

    /// Resend requests for orphaned drafts — empty assistant messages with no responseId.
    /// This happens when the user sends a message and immediately force-quits the app
    /// before the SSE stream receives the response.created event.
    private func resendOrphanedDrafts() async {
        guard !apiKey.isEmpty else { return }

        // Find all incomplete assistant messages with no responseId and no content
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.isComplete == false && message.responseId == nil
            }
        )

        guard let orphanedDrafts = try? modelContext.fetch(descriptor) else { return }

        // Only process assistant drafts that are empty (the ones created right before streaming)
        let draftsToResend = orphanedDrafts.filter { $0.role == .assistant && $0.content.isEmpty }

        #if DEBUG
        if !draftsToResend.isEmpty {
            print("[Recovery] Found \(draftsToResend.count) orphaned draft(s) to resend")
        }
        #endif

        for draft in draftsToResend {
            guard let conversation = draft.conversation else {
                // No conversation — just delete the orphan
                modelContext.delete(draft)
                try? modelContext.save()
                continue
            }

            // Find the last user message in this conversation
            let userMessages = conversation.messages
                .filter { $0.role == .user }
                .sorted { $0.createdAt < $1.createdAt }

            guard let lastUserMessage = userMessages.last else {
                // No user message to resend — delete the orphan
                modelContext.delete(draft)
                try? modelContext.save()
                continue
            }

            #if DEBUG
            print("[Recovery] Resending request for orphaned draft in conversation: \(conversation.title)")
            #endif

            // Load this conversation if it's the current one (or make it current)
            if currentConversation?.id != conversation.id {
                loadConversation(conversation)
            }

            // Remove the empty draft — we'll create a new one via the normal send flow
            if let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
                conversation.messages.remove(at: idx)
            }
            messages.removeAll { $0.id == draft.id }
            modelContext.delete(draft)
            try? modelContext.save()

            // Now re-create a draft and start streaming (same as sendMessage but without user message)
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
            isThinking = false
            currentStreamingText = ""
            currentThinkingText = ""

            // Use the conversation's saved model/effort
            let convModel = ModelType(rawValue: conversation.model) ?? .gpt5_4
            let convEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
            selectedModel = convModel
            reasoningEffort = convEffort

            startStreamingRequest()

            // Only resend one at a time — wait for it to complete before processing the next
            // (the streaming will handle itself asynchronously)
            return
        }
    }

    /// Check the current conversation for incomplete messages.
    private func recoverIncompleteMessagesInCurrentConversation() async {
        guard !apiKey.isEmpty else { return }
        guard let conversation = currentConversation else { return }

        let incompleteMessages = conversation.messages.filter {
            $0.role == .assistant && !$0.isComplete && $0.responseId != nil
        }

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }
            await recoverSingleMessage(message: message, responseId: responseId)
        }
    }

    /// Recover a single message by polling.
    private func recoverSingleMessage(message: Message, responseId: String) async {
        let key = apiKey
        var attempts = 0
        let maxAttempts = 150

        while attempts < maxAttempts {
            attempts += 1

            do {
                let result = try await openAIService.fetchResponse(responseId: responseId, apiKey: key)

                // Success
                if !result.text.isEmpty {
                    message.content = result.text
                }
                if let thinking = result.thinking, !thinking.isEmpty {
                    message.thinking = thinking
                }
                message.isComplete = true
                try? modelContext.save()

                // Update UI if this message is in the current view
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

        // Mark as complete to avoid infinite retry loops
        message.isComplete = true
        if message.content.isEmpty {
            message.content = "[Response interrupted. Please try again.]"
        }
        try? modelContext.save()
    }

    /// Find a message by ID in the model context.
    private func findMessage(byId id: UUID) -> Message? {
        // First check the in-memory messages array
        if let msg = messages.first(where: { $0.id == id }) {
            return msg
        }
        // Then check the draft
        if let draft = draftMessage, draft.id == id {
            return draft
        }
        // Finally try fetching from SwiftData
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
            finalizeDraft()
        } else if let draft = draftMessage, !draft.content.isEmpty {
            // Draft already has content from periodic saves
            draft.isComplete = true
            try? modelContext.save()
            if !messages.contains(where: { $0.id == draft.id }) {
                messages.append(draft)
            }
            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
            isThinking = false
            draftMessage = nil
        } else {
            removeEmptyDraft()
            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
            isThinking = false
        }

        isRecovering = false
        endBackgroundTask()
        HapticService.shared.impact(.medium)
    }

    // MARK: - New Chat

    func startNewChat() {
        if isStreaming {
            // Save partial content before switching
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
        isThinking = false
        isRecovering = false
        draftMessage = nil
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

        // Remove the assistant message from the array and SwiftData
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: index)
        }
        if let conversation = currentConversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }
        modelContext.delete(message)
        try? modelContext.save()

        // Clear state
        errorMessage = nil

        // Create draft for the regenerated response
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
            // Filter out empty draft messages that might have been left over
            .filter { !($0.role == .assistant && $0.content.isEmpty && !$0.isComplete) }
        selectedModel = ModelType(rawValue: conversation.model) ?? .gpt5_4
        reasoningEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high

        // Validate effort for loaded model
        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
        }

        currentStreamingText = ""
        currentThinkingText = ""
        errorMessage = nil
        isThinking = false
        isRecovering = false
        draftMessage = nil

        // Check for incomplete messages in this conversation and recover them
        Task { @MainActor in
            await recoverIncompleteMessagesInCurrentConversation()
        }
    }

    // MARK: - Restore Last Conversation

    /// On app launch, restore the most recently updated conversation so the user
    /// sees their previous chat instead of an empty screen.
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

        // Brief delay so the UI has time to render the restoring indicator
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        isRestoringConversation = false
    }

    /// Generate titles for any conversations that are still "New Chat" but have messages.
    /// This handles the case where the user exited before title generation completed.
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

                // Update the current conversation title in the UI if it matches
                if conversation.id == currentConversation?.id {
                    currentConversation?.title = title
                }

                #if DEBUG
                print("[Title] Generated title for conversation \(conversation.id): \(title)")
                #endif
            } catch {
                // Non-critical
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
