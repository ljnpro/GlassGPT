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

    func makeRecoverySession(for message: Message) -> ResponseSession? {
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

    func registerSession(_ session: ResponseSession, visible: Bool) {
        sessionRegistry.register(session, visible: visible) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }

        if visible {
            bindVisibleSession(messageID: session.messageID)
        } else if visibleSessionMessageID == session.messageID {
            syncVisibleState(from: session)
        }
    }

    func isSessionActive(_ session: ResponseSession) -> Bool {
        sessionRegistry.contains(session)
    }

    func bindVisibleSession(messageID: UUID?) {
        sessionRegistry.bindVisibleSession(messageID: messageID)

        guard
            let messageID,
            let session = sessionRegistry.session(for: messageID),
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

    func detachVisibleSessionBinding() {
        sessionRegistry.bindVisibleSession(messageID: nil)
        draftMessage = nil
        clearLiveGenerationState(clearDraft: false)
        errorMessage = nil
    }

    func setVisibleRecoveryPhase(_ phase: RecoveryPhase) {
        visibleRecoveryPhase = phase
        isRecovering = phase == .streamResuming
    }

    func setRecoveryPhase(_ phase: RecoveryPhase, for session: ResponseSession) {
        session.recoveryPhase = phase
        if visibleSessionMessageID == session.messageID {
            setVisibleRecoveryPhase(phase)
        }
    }

    func syncVisibleState(from session: ResponseSession) {
        guard visibleSessionMessageID == session.messageID else { return }

        let state = SessionVisibilityCoordinator.visibleState(
            from: session,
            draftMessage: findMessage(byId: session.messageID)
        )
        applyVisibleState(state)
    }

    func saveSessionIfNeeded(_ session: ResponseSession) {
        let now = Date()
        let minimumInterval = session.requestUsesBackgroundMode ? 0.25 : 2.0
        guard now.timeIntervalSince(session.lastDraftSaveTime) >= minimumInterval else { return }
        saveSessionNow(session)
    }

    func saveSessionNow(_ session: ResponseSession) {
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

        saveContextIfPossible("saveSessionNow")

        if message.conversation?.id == currentConversation?.id {
            upsertMessage(message)
        }

        syncVisibleState(from: session)
    }

    func finalizeSession(_ session: ResponseSession) {
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
        saveContextIfPossible("finalizeSession")
        prefetchGeneratedFilesIfNeeded(for: message)

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

    func finalizeSessionAsPartial(_ session: ResponseSession) {
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
        saveContextIfPossible("finalizeSessionAsPartial")
        prefetchGeneratedFilesIfNeeded(for: message)

        removeSession(session)
    }

    func removeEmptyMessage(_ message: Message, for session: ResponseSession) {
        if let conversation = message.conversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: idx)
        }

        conversationRepository.delete(message)
        saveContextIfPossible("removeEmptyMessage")
        removeSession(session)
    }

    func removeSession(_ session: ResponseSession) {
        let wasVisible = visibleSessionMessageID == session.messageID
        sessionRegistry.remove(session) { target in
            target.task?.cancel()
            target.service.cancelStream()
        }

        if wasVisible {
            refreshVisibleBindingForCurrentConversation()
        }
    }

    func refreshVisibleBindingForCurrentConversation() {
        guard let conversation = currentConversation else {
            detachVisibleSessionBinding()
            return
        }

        let activeMessages = conversation.messages
            .filter { $0.role == .assistant && !$0.isComplete }
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let message = activeMessages.last(where: { sessionRegistry.session(for: $0.id) != nil }) {
            bindVisibleSession(messageID: message.id)
            return
        }

        if let message = activeMessages.last {
            sessionRegistry.bindVisibleSession(messageID: nil)
            clearLiveGenerationState(clearDraft: false)
            draftMessage = message
        } else {
            detachVisibleSessionBinding()
        }
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
        applyVisibleState(
            SessionVisibilityCoordinator.clearedState(
                retaining: draftMessage,
                clearDraft: clearDraft
            )
        )
    }

    func suspendActiveSessionsForAppBackground() {
        let sessions = sessionRegistry.allSessions
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

        saveContextIfPossible("suspendActiveSessionsForAppBackground")
        sessionRegistry.removeAll { session in
            session.task?.cancel()
            session.service.cancelStream()
        }
        detachVisibleSessionBinding()
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
