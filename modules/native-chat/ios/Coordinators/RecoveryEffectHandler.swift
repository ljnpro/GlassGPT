import Foundation

@MainActor
final class RecoveryEffectHandler {
    unowned let viewModel: ChatScreenStore

    init(viewModel: ChatScreenStore) {
        self.viewModel = viewModel
    }

    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        guard !viewModel.apiKey.isEmpty else { return }
        guard let message = viewModel.findMessage(byId: messageId) else { return }

        let session: ResponseSession
        if let existing = viewModel.sessionRegistry.session(for: messageId) {
            session = existing
        } else if let created = viewModel.makeRecoverySession(for: message) {
            session = created
            viewModel.registerSession(created, visible: visible)
        } else {
            return
        }

        if viewModel.isSessionActive(session),
           session.task != nil,
           session.responseId == responseId {
            if visible {
                viewModel.bindVisibleSession(messageID: messageId)
            }
            return
        }

        session.beginRecoveryCheck(responseId: responseId)
        viewModel.setRecoveryPhase(.checkingStatus, for: session)

        if visible {
            viewModel.errorMessage = nil
            viewModel.bindVisibleSession(messageID: messageId)
        }

        session.task?.cancel()
        session.task = Task { @MainActor in
            guard self.viewModel.isSessionActive(session) else { return }

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: self.viewModel.apiKey)

                switch result.status {
                case .completed:
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )

                case .failed, .incomplete, .unknown:
                    if visible {
                        self.viewModel.errorMessage = result.errorMessage ?? "Response did not complete."
                    }
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )

                case .queued, .inProgress:
                    switch ChatSessionDecisions.recoveryResumeMode(
                        preferStreamingResume: preferStreamingResume,
                        usedBackgroundMode: message.usedBackgroundMode,
                        lastSequenceNumber: message.lastSequenceNumber
                    ) {
                    case .stream(let lastSequenceNumber):
                        await self.startStreamingRecovery(
                            session: session,
                            responseId: responseId,
                            lastSeq: lastSequenceNumber,
                            apiKey: self.viewModel.apiKey
                        )
                    case .poll:
                        await self.pollResponseUntilTerminal(session: session, responseId: responseId)
                    }
                }
            } catch {
                if self.handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: visible
                ) {
                    return
                }

                #if DEBUG
                Loggers.recovery.debug("[Recovery] Status fetch failed for \(responseId): \(error.localizedDescription)")
                #endif
                await self.pollResponseUntilTerminal(session: session, responseId: responseId)
            }
        }
    }
}
