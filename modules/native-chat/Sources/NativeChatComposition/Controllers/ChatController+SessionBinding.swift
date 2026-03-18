import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatController {
    func makeRecoverySession(for message: Message) -> ReplySession? {
        guard let conversation = message.conversation else { return nil }
        let configuration = sessionRequestConfiguration(for: conversation)

        return ReplySession(
            assistantReplyID: AssistantReplyID(rawValue: message.id),
            message: message,
            conversationID: conversation.id,
            request: ResponseRequestContext(
                apiKey: apiKey,
                messages: nil,
                model: configuration.0,
                effort: configuration.1,
                usesBackgroundMode: message.usedBackgroundMode,
                serviceTier: configuration.2
            )
        )
    }

    func registerSession(_ session: ReplySession, execution: SessionExecutionState, visible: Bool) {
        sessionRegistry.register(session, execution: execution, visible: visible) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }
        ensureRuntimeSessionRegistered(for: session)

        if visible {
            bindVisibleSession(messageID: session.messageID)
        } else if visibleSessionMessageID == session.messageID {
            syncVisibleState(from: session)
        }
    }

    func isSessionActive(_ session: ReplySession) -> Bool {
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
            clearVisibleState(clearDraft: false)
            return
        }

        draftMessage = message
        syncVisibleState(from: session)
        upsertMessage(message)
    }

    func detachVisibleSessionBinding() {
        sessionRegistry.bindVisibleSession(messageID: nil)
        draftMessage = nil
        clearVisibleState(clearDraft: false)
        errorMessage = nil
    }

    func setVisibleRecoveryPhase(_ phase: RecoveryPhase) {
        visibleRecoveryPhase = phase
        isRecovering = phase == .streamResuming
    }

    func setRecoveryPhase(_ phase: RecoveryPhase, for session: ReplySession) {
        session.setRecoveryPhase(phase)
        syncRuntimeSession(from: session)
        if visibleSessionMessageID == session.messageID {
            setVisibleRecoveryPhase(phase)
        }
    }

    func syncVisibleState(from session: ReplySession) {
        syncRuntimeSession(from: session)
        guard visibleSessionMessageID == session.messageID else { return }

        let state = SessionVisibilityCoordinator.visibleState(
            from: session,
            draftMessage: findMessage(byId: session.messageID)
        )
        applyVisibleState(state)
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
            clearVisibleState(clearDraft: false)
            draftMessage = message
        } else {
            detachVisibleSessionBinding()
        }
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

    func clearLiveGenerationState(clearDraft: Bool) {
        clearVisibleState(clearDraft: clearDraft)
    }

    func syncConversationProjection() {
        // Visible state now lives directly on the controller.
    }

    private func clearVisibleState(clearDraft: Bool) {
        applyVisibleState(
            SessionVisibilityCoordinator.clearedState(
                retaining: draftMessage,
                clearDraft: clearDraft
            )
        )
    }
}
