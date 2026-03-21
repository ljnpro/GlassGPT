import ChatRuntimeModel
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func persistToolCallsAndCitations() {
        guard let session = currentVisibleSession else { return }
        saveSessionNow(session)
    }

    func saveDraftIfNeeded() {
        guard let session = currentVisibleSession else { return }
        saveSessionIfNeeded(session)
    }

    func saveDraftNow() {
        guard let session = currentVisibleSession else { return }
        saveSessionNow(session)
    }

    func finalizeDraft() {
        guard let session = currentVisibleSession else {
            clearLiveGenerationState(clearDraft: true)
            return
        }
        finalizeSession(session)
    }

    func finalizeDraftAsPartial() {
        guard let session = currentVisibleSession else { return }
        finalizeSessionAsPartial(session)
    }

    func removeEmptyDraft() {
        guard let session = currentVisibleSession, let draft = state.draftMessage else { return }
        removeEmptyMessage(draft, for: session)
    }

    func stopGeneration(savePartial: Bool = true) {
        guard let session = currentVisibleSession else { return }
        let runtimeState = cachedRuntimeState(for: session)

        let pendingBackgroundCancellation = RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
            requestUsesBackgroundMode: session.request.usesBackgroundMode,
            responseId: runtimeState?.responseID,
            messageId: session.messageID
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await applyRuntimeTransition(.cancelStreaming, to: session)
        }
        if let execution = services.sessionRegistry.execution(for: session.messageID) {
            execution.service.cancelStream()
            execution.task?.cancel()
        }
        state.errorMessage = nil

        if savePartial, !(runtimeState?.buffer.text.isEmpty ?? true) {
            persistToolCallsAndCitations()
            finalizeSession(session)
        } else if let draft = conversations.findMessage(byId: session.messageID) {
            if let runtimeState, !runtimeState.buffer.text.isEmpty {
                draft.content = runtimeState.buffer.text
            }
            if let runtimeState, !runtimeState.buffer.thinking.isEmpty {
                draft.thinking = runtimeState.buffer.thinking
            }
            if !draft.content.isEmpty {
                draft.isComplete = true
                draft.lastSequenceNumber = nil
                conversations.saveContextIfPossible("stopGeneration.persistPartialDraft")
                conversations.upsertMessage(draft)
                removeSession(session)
            } else {
                removeEmptyMessage(draft, for: session)
            }
        }

        services.endBackgroundTask()
        state.hapticService.impact(.medium, isEnabled: state.hapticsEnabled)

        if let pendingBackgroundCancellation {
            guard let recovery else { return }
            Task { @MainActor [weak self, recovery] in
                guard self != nil else { return }
                await recovery.cancelBackgroundResponseAndSync(
                    responseId: pendingBackgroundCancellation.responseId,
                    messageId: pendingBackgroundCancellation.messageId
                )
            }
        }
    }
}
