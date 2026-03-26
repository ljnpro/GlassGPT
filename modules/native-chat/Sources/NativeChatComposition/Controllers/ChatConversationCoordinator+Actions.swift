import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
package extension ChatConversationCoordinator {
    /// Resets the active conversation state, saving any visible session first.
    func startNewChat() {
        if let session = sessions.currentVisibleSession {
            sessions.saveSessionNow(session)
        }

        services.cancelGeneratedFilePrefetches(services.generatedFilePrefetchRegistry.cancelAll())
        sessions.detachVisibleSessionBinding()
        state.currentConversation = nil
        state.messages = []
        state.currentStreamingText = ""
        state.currentThinkingText = ""
        state.errorMessage = nil
        state.selectedImageData = nil
        state.pendingAttachments = []
        state.isThinking = false
        state.thinkingPresentationState = nil
        state.draftMessage = nil
        state.activeToolCalls = []
        state.liveCitations = []
        state.liveFilePathAnnotations = []
        state.lastSequenceNumber = nil
        state.activeRequestUsesBackgroundMode = false
        state.filePreviewItem = nil
        state.sharedGeneratedFileItem = nil
        state.fileDownloadError = nil
        loadDefaultsFromSettings()
        state.syncConversationProjection()
        state.hapticService.selection(isEnabled: state.hapticsEnabled)
    }

    /// Deletes the given assistant message and re-submits a fresh request for it.
    func regenerateMessage(_ message: Message) {
        guard !state.isStreaming else { return }
        guard message.role == .assistant else { return }
        guard !drafts.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.errorMessage = "Please add your OpenAI API key in Settings."
            return
        }

        if let index = state.messages.firstIndex(where: { $0.id == message.id }) {
            state.messages.remove(at: index)
        }

        if let conversation = state.currentConversation,
           let idx = conversation.messages.firstIndex(where: { $0.id == message.id }) {
            conversation.messages.remove(at: idx)
        }

        services.conversationRepository.delete(message)
        saveContextIfPossible("regenerateMessage.deleteOriginal")

        state.errorMessage = nil

        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            lastSequenceNumber: nil,
            usedBackgroundMode: state.backgroundModeEnabled,
            isComplete: false
        )
        draft.conversation = state.currentConversation
        state.currentConversation?.messages.append(draft)
        saveContextIfPossible("regenerateMessage.insertDraft")

        let preparedReply: PreparedAssistantReply
        do {
            preparedReply = try drafts.prepareExistingDraft(draft)
        } catch SendMessagePreparationError.missingAPIKey {
            state.errorMessage = "Please add your OpenAI API key in Settings."
            return
        } catch {
            state.errorMessage = "Failed to start response session."
            return
        }

        let session = ReplySession(preparedReply: preparedReply)
        sessions.registerSession(
            session,
            execution: SessionExecutionState(service: services.serviceFactory()),
            visible: true,
            syncIfCurrentlyVisible: true
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await sessions.applyRuntimeTransition(.beginSubmitting, to: session)
            sessions.syncVisibleState(from: session)
        }

        state.hapticService.impact(.medium, isEnabled: state.hapticsEnabled)
        streaming.startStreamingRequest(for: session, reconnectAttempt: 0)
    }
}
