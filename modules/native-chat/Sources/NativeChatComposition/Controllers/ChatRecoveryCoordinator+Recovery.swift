import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatRecoveryCoordinator {
    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        guard !controller.apiKey.isEmpty else { return }
        guard let message = controller.findMessage(byId: messageId) else { return }

        let session: ReplySession
        if let existing = controller.sessionRegistry.session(for: messageId) {
            session = existing
        } else if let created = controller.makeRecoverySession(for: message) {
            session = created
            controller.registerSession(
                created,
                execution: SessionExecutionState(service: controller.serviceFactory()),
                visible: visible
            )
        } else {
            return
        }

        if controller.isSessionActive(session),
           controller.sessionRegistry.execution(for: messageId)?.task != nil,
           controller.cachedRuntimeState(for: session)?.responseID == responseId {
            if visible {
                controller.bindVisibleSession(messageID: messageId)
            }
            return
        }

        let controller = controller
        Task { @MainActor in
            _ = await controller.applyRuntimeTransition(
                .beginRecoveryStatus(
                    responseID: responseId,
                    lastSequenceNumber: message.lastSequenceNumber,
                    usedBackgroundMode: message.usedBackgroundMode,
                    route: controller.runtimeRoute(for: session)
                ),
                to: session
            )
            controller.syncVisibleState(from: session)
        }

        if visible {
            controller.errorMessage = nil
            controller.bindVisibleSession(messageID: messageId)
        }

        let execution = controller.sessionRegistry.execution(for: messageId) ?? SessionExecutionState(service: controller.serviceFactory())
        controller.sessionRegistry.registerExecution(execution, for: messageId) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }

        execution.task?.cancel()
        execution.task = Task { @MainActor in
            guard controller.isSessionActive(session) else { return }
            let apiKey = self.activeAPIKey(for: session)

            do {
                let result = try await execution.service.fetchResponse(responseId: responseId, apiKey: apiKey)

                switch result.status {
                case .completed:
                    self.controller.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )

                case .failed, .incomplete, .unknown:
                    if visible {
                        controller.errorMessage = result.errorMessage ?? "Response did not complete."
                    }
                    self.controller.finishRecovery(
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
                        await self.controller.startStreamingRecovery(
                            session: session,
                            responseId: responseId,
                            lastSeq: lastSequenceNumber,
                            apiKey: apiKey
                        )
                    case .poll:
                        await self.controller.pollResponseUntilTerminal(session: session, responseId: responseId)
                    }
                }
            } catch {
                if self.controller.handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: visible
                ) {
                    return
                }
                await self.controller.pollResponseUntilTerminal(session: session, responseId: responseId)
            }
        }
    }
}
