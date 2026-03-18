import ChatDomain
import ChatRuntimeModel
import ChatUIComponents
import Foundation

@MainActor
extension ChatController {
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
        guard let session = currentVisibleSession, let draft = draftMessage else { return }
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

        Task { @MainActor in
            _ = await applyRuntimeTransition(.cancelStreaming, to: session)
        }
        if let execution = sessionRegistry.execution(for: session.messageID) {
            execution.service.cancelStream()
            execution.task?.cancel()
        }
        errorMessage = nil

        if savePartial && !(runtimeState?.buffer.text.isEmpty ?? true) {
            persistToolCallsAndCitations()
            finalizeSession(session)
        } else if let draft = findMessage(byId: session.messageID) {
            if let runtimeState, !runtimeState.buffer.text.isEmpty {
                draft.content = runtimeState.buffer.text
            }
            if let runtimeState, !runtimeState.buffer.thinking.isEmpty {
                draft.thinking = runtimeState.buffer.thinking
            }
            if !draft.content.isEmpty {
                draft.isComplete = true
                draft.lastSequenceNumber = nil
                saveContextIfPossible("stopGeneration.persistPartialDraft")
                upsertMessage(draft)
                removeSession(session)
            } else {
                removeEmptyMessage(draft, for: session)
            }
        }

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
}
