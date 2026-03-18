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
            setVisibleRecoveryPhase(.idle)
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

        let pendingBackgroundCancellation = RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
            requestUsesBackgroundMode: session.request.usesBackgroundMode,
            responseId: session.responseId,
            messageId: session.messageID
        )

        session.cancelStreaming()
        if let execution = sessionRegistry.execution(for: session.messageID) {
            execution.service.cancelStream()
            execution.task?.cancel()
        }
        errorMessage = nil

        if savePartial && !session.currentText.isEmpty {
            persistToolCallsAndCitations()
            finalizeSession(session)
        } else if let draft = findMessage(byId: session.messageID) {
            if !session.currentText.isEmpty {
                draft.content = session.currentText
            }
            if !session.currentThinking.isEmpty {
                draft.thinking = session.currentThinking
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

        setVisibleRecoveryPhase(.idle)
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
