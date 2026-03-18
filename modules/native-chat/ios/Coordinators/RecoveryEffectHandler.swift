import Foundation

@MainActor
final class RecoveryEffectHandler {
    unowned let viewModel: any ChatRuntimeScreenStore

    init(viewModel: any ChatRuntimeScreenStore) {
        self.viewModel = viewModel
    }

    func activeAPIKey(for session: ResponseSession) -> String {
        let key = session.requestAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? viewModel.apiKey : key
    }

    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        let viewModel = self.viewModel
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
            guard viewModel.isSessionActive(session) else { return }
            let apiKey = self.activeAPIKey(for: session)

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: apiKey)

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
                        viewModel.errorMessage = result.errorMessage ?? "Response did not complete."
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
                            apiKey: apiKey
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
