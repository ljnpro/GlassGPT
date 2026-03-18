import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatController {
    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        guard !apiKey.isEmpty else { return }
        guard let message = findMessage(byId: messageId) else { return }

        let session: ReplySession
        if let existing = sessionRegistry.session(for: messageId) {
            session = existing
        } else if let created = makeRecoverySession(for: message) {
            session = created
            registerSession(created, execution: SessionExecutionState(service: serviceFactory()), visible: visible)
        } else {
            return
        }

        if isSessionActive(session),
           sessionRegistry.execution(for: messageId)?.task != nil,
           session.responseId == responseId {
            if visible {
                bindVisibleSession(messageID: messageId)
            }
            return
        }

        session.beginRecoveryCheck(responseId: responseId)
        setRecoveryPhase(.checkingStatus, for: session)

        if visible {
            errorMessage = nil
            bindVisibleSession(messageID: messageId)
        }

        let execution = sessionRegistry.execution(for: messageId) ?? SessionExecutionState(service: serviceFactory())
        sessionRegistry.registerExecution(execution, for: messageId) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }

        execution.task?.cancel()
        execution.task = Task { @MainActor in
            guard isSessionActive(session) else { return }
            let apiKey = self.activeAPIKey(for: session)

            do {
                let result = try await execution.service.fetchResponse(responseId: responseId, apiKey: apiKey)

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
                        errorMessage = result.errorMessage ?? "Response did not complete."
                    }
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )

                case .queued, .inProgress:
                    switch RuntimeSessionDecisionPolicy.recoveryResumeMode(
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
                await self.pollResponseUntilTerminal(session: session, responseId: responseId)
            }
        }
    }
}
