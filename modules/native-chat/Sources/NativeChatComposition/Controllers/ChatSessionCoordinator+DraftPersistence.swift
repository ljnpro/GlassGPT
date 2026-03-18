import ChatRuntimeModel
import Foundation

@MainActor
extension ChatSessionCoordinator {
    func persistToolCallsAndCitations() {
        guard let session = controller.currentVisibleSession else { return }
        saveSessionNow(session)
    }

    func saveDraftIfNeeded() {
        guard let session = controller.currentVisibleSession else { return }
        saveSessionIfNeeded(session)
    }

    func saveDraftNow() {
        guard let session = controller.currentVisibleSession else { return }
        saveSessionNow(session)
    }

    func finalizeDraft() {
        guard let session = controller.currentVisibleSession else {
            clearLiveGenerationState(clearDraft: true)
            return
        }
        finalizeSession(session)
    }

    func finalizeDraftAsPartial() {
        guard let session = controller.currentVisibleSession else { return }
        finalizeSessionAsPartial(session)
    }

    func removeEmptyDraft() {
        guard let session = controller.currentVisibleSession, let draft = controller.draftMessage else { return }
        removeEmptyMessage(draft, for: session)
    }

    func stopGeneration(savePartial: Bool = true) {
        guard let session = controller.currentVisibleSession else { return }
        let runtimeState = cachedRuntimeState(for: session)

        let pendingBackgroundCancellation = RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
            requestUsesBackgroundMode: session.request.usesBackgroundMode,
            responseId: runtimeState?.responseID,
            messageId: session.messageID
        )

        Task { @MainActor in
            _ = await applyRuntimeTransition(.cancelStreaming, to: session)
        }
        if let execution = controller.sessionRegistry.execution(for: session.messageID) {
            execution.service.cancelStream()
            execution.task?.cancel()
        }
        controller.errorMessage = nil

        if savePartial && !(runtimeState?.buffer.text.isEmpty ?? true) {
            persistToolCallsAndCitations()
            finalizeSession(session)
        } else if let draft = controller.conversationCoordinator.findMessage(byId: session.messageID) {
            if let runtimeState, !runtimeState.buffer.text.isEmpty {
                draft.content = runtimeState.buffer.text
            }
            if let runtimeState, !runtimeState.buffer.thinking.isEmpty {
                draft.thinking = runtimeState.buffer.thinking
            }
            if !draft.content.isEmpty {
                draft.isComplete = true
                draft.lastSequenceNumber = nil
                controller.conversationCoordinator.saveContextIfPossible("stopGeneration.persistPartialDraft")
                controller.conversationCoordinator.upsertMessage(draft)
                removeSession(session)
            } else {
                removeEmptyMessage(draft, for: session)
            }
        }

        controller.endBackgroundTask()
        controller.hapticService.impact(.medium, isEnabled: controller.hapticsEnabled)

        if let pendingBackgroundCancellation {
            Task { @MainActor in
                await self.controller.cancelBackgroundResponseAndSync(
                    responseId: pendingBackgroundCancellation.responseId,
                    messageId: pendingBackgroundCancellation.messageId
                )
            }
        }
    }
}
