import Foundation

@MainActor
extension StreamingEffectHandler {
    func persistToolCallsAndCitations() {
        guard let session = viewModel.currentVisibleSession else { return }
        viewModel.saveSessionNow(session)
    }

    func saveDraftIfNeeded() {
        guard let session = viewModel.currentVisibleSession else { return }
        viewModel.saveSessionIfNeeded(session)
    }

    func saveDraftNow() {
        guard let session = viewModel.currentVisibleSession else { return }
        viewModel.saveSessionNow(session)
    }

    func finalizeDraft() {
        guard let session = viewModel.currentVisibleSession else {
            viewModel.clearLiveGenerationState(clearDraft: true)
            viewModel.setVisibleRecoveryPhase(.idle)
            return
        }
        viewModel.finalizeSession(session)
    }

    func finalizeDraftAsPartial() {
        guard let session = viewModel.currentVisibleSession else { return }
        viewModel.finalizeSessionAsPartial(session)
    }

    func removeEmptyDraft() {
        guard let session = viewModel.currentVisibleSession, let draft = viewModel.draftMessage else { return }
        viewModel.removeEmptyMessage(draft, for: session)
    }

    func stopGeneration(savePartial: Bool = true) {
        guard let session = viewModel.currentVisibleSession else { return }

        let pendingBackgroundCancellation = ChatSessionDecisions.pendingBackgroundCancellation(
            requestUsesBackgroundMode: session.requestUsesBackgroundMode,
            responseId: session.responseId,
            messageId: session.messageID
        )

        session.cancelStreaming()
        session.service.cancelStream()
        session.task?.cancel()
        viewModel.errorMessage = nil

        if savePartial && !session.currentText.isEmpty {
            persistToolCallsAndCitations()
            viewModel.finalizeSession(session)
        } else if let draft = viewModel.findMessage(byId: session.messageID) {
            if !session.currentText.isEmpty {
                draft.content = session.currentText
            }
            if !session.currentThinking.isEmpty {
                draft.thinking = session.currentThinking
            }
            if !draft.content.isEmpty {
                draft.isComplete = true
                draft.lastSequenceNumber = nil
                viewModel.saveContextIfPossible("stopGeneration.persistPartialDraft")
                viewModel.upsertMessage(draft)
                viewModel.removeSession(session)
            } else {
                viewModel.removeEmptyMessage(draft, for: session)
            }
        }

        viewModel.setVisibleRecoveryPhase(.idle)
        viewModel.endBackgroundTask()
        HapticService.shared.impact(.medium)

        if let pendingBackgroundCancellation {
            let recoveryCoordinator = self.recoveryCoordinator
            Task { @MainActor in
                await recoveryCoordinator.cancelBackgroundResponseAndSync(
                    responseId: pendingBackgroundCancellation.responseId,
                    messageId: pendingBackgroundCancellation.messageId
                )
            }
        }
    }
}
