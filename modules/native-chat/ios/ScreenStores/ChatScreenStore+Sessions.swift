import Foundation

@MainActor
extension ChatViewModel {

    // MARK: - Session Management

    func sessionRequestConfiguration(for conversation: Conversation?) -> (ModelType, ReasoningEffort, ServiceTier) {
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

    func buildRequestMessages(for conversation: Conversation, excludingDraft draftID: UUID) -> [APIMessage] {
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

    func makeStreamingSession(for draft: Message) -> ResponseSession? {
        conversationRuntime.sessionStateStore.makeStreamingSession(for: draft)
    }

    func makeRecoverySession(for message: Message) -> ResponseSession? {
        conversationRuntime.sessionStateStore.makeRecoverySession(for: message)
    }

    func registerSession(_ session: ResponseSession, visible: Bool) {
        conversationRuntime.sessionStateStore.registerSession(session, visible: visible)
    }

    func isSessionActive(_ session: ResponseSession) -> Bool {
        conversationRuntime.sessionStateStore.isSessionActive(session)
    }

    func bindVisibleSession(messageID: UUID?) {
        conversationRuntime.sessionStateStore.bindVisibleSession(messageID: messageID)
    }

    func detachVisibleSessionBinding() {
        conversationRuntime.sessionStateStore.detachVisibleSessionBinding()
    }

    func setVisibleRecoveryPhase(_ phase: RecoveryPhase) {
        visibleRecoveryPhase = phase
        isRecovering = phase == .streamResuming
    }

    func setRecoveryPhase(_ phase: RecoveryPhase, for session: ResponseSession) {
        conversationRuntime.sessionStateStore.setRecoveryPhase(phase, for: session)
    }

    func syncVisibleState(from session: ResponseSession) {
        conversationRuntime.sessionStateStore.syncVisibleState(from: session)
    }

    func saveSessionIfNeeded(_ session: ResponseSession) {
        conversationRuntime.sessionStateStore.saveSessionIfNeeded(session)
    }

    func saveSessionNow(_ session: ResponseSession) {
        conversationRuntime.sessionStateStore.saveSessionNow(session)
    }

    func finalizeSession(_ session: ResponseSession) {
        conversationRuntime.sessionStateStore.finalizeSession(session)
    }

    func finalizeSessionAsPartial(_ session: ResponseSession) {
        conversationRuntime.sessionStateStore.finalizeSessionAsPartial(session)
    }

    func removeEmptyMessage(_ message: Message, for session: ResponseSession) {
        conversationRuntime.sessionStateStore.removeEmptyMessage(message, for: session)
    }

    func removeSession(_ session: ResponseSession) {
        conversationRuntime.sessionStateStore.removeSession(session)
    }

    func refreshVisibleBindingForCurrentConversation() {
        conversationRuntime.sessionStateStore.refreshVisibleBindingForCurrentConversation()
    }

    // MARK: - Helpers

    func visibleMessages(for conversation: Conversation) -> [Message] {
        conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .filter { !shouldHideMessage($0) }
    }

    func shouldHideMessage(_ message: Message) -> Bool {
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

    func syncConversationConfiguration() {
        guard let currentConversation else { return }
        currentConversation.model = selectedModel.rawValue
        currentConversation.reasoningEffort = reasoningEffort.rawValue
        currentConversation.backgroundModeEnabled = backgroundModeEnabled
        currentConversation.serviceTierRawValue = serviceTier.rawValue
        currentConversation.updatedAt = .now
        saveContextIfPossible("syncConversationConfiguration")
    }

    func upsertMessage(_ message: Message) {
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

    func clearLiveGenerationState(clearDraft: Bool) {
        conversationRuntime.sessionStateStore.clearLiveGenerationState(clearDraft: clearDraft)
    }

    func suspendActiveSessionsForAppBackground() {
        conversationRuntime.sessionStateStore.suspendActiveSessionsForAppBackground()
    }

    func applyVisibleState(_ state: ChatVisibleSessionState) {
        draftMessage = state.draftMessage
        currentStreamingText = state.currentStreamingText
        currentThinkingText = state.currentThinkingText
        activeToolCalls = state.activeToolCalls
        liveCitations = state.liveCitations
        liveFilePathAnnotations = state.liveFilePathAnnotations
        lastSequenceNumber = state.lastSequenceNumber
        activeRequestModel = state.activeRequestModel
        activeRequestEffort = state.activeRequestEffort
        activeRequestUsesBackgroundMode = state.activeRequestUsesBackgroundMode
        activeRequestServiceTier = state.activeRequestServiceTier
        isStreaming = state.isStreaming
        isThinking = state.isThinking
        visibleRecoveryPhase = state.visibleRecoveryPhase
        isRecovering = state.isRecovering
    }
}
