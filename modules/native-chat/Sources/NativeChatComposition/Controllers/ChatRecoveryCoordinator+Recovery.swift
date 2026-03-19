import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatRecoveryCoordinator {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        guard !controller.apiKey.isEmpty else { return }
        guard let message = controller.conversationCoordinator.findMessage(byId: messageId) else { return }

        let session: ReplySession
        if let existing = controller.sessionRegistry.session(for: messageId) {
            session = existing
        } else if let created = controller.sessionCoordinator.makeRecoverySession(for: message) {
            session = created
            controller.sessionCoordinator.registerSession(
                created,
                execution: SessionExecutionState(service: controller.serviceFactory()),
                visible: visible
            )
        } else {
            return
        }

        if controller.sessionCoordinator.isSessionActive(session),
           controller.sessionRegistry.execution(for: messageId)?.task != nil,
           controller.sessionCoordinator.cachedRuntimeState(for: session)?.responseID == responseId {
            if visible {
                controller.sessionCoordinator.bindVisibleSession(messageID: messageId)
            }
            return
        }

        let controller = controller
        Task { @MainActor in
            _ = await controller.sessionCoordinator.applyRuntimeTransition(
                .beginRecoveryStatus(
                    responseID: responseId,
                    lastSequenceNumber: message.lastSequenceNumber,
                    usedBackgroundMode: message.usedBackgroundMode,
                    route: controller.sessionCoordinator.runtimeRoute(for: session)
                ),
                to: session
            )
            controller.sessionCoordinator.syncVisibleState(from: session)
        }

        if visible {
            controller.errorMessage = nil
            controller.sessionCoordinator.bindVisibleSession(messageID: messageId)
        }

        let execution = controller.sessionRegistry.execution(for: messageId) ?? SessionExecutionState(service: controller.serviceFactory())
        controller.sessionRegistry.registerExecution(execution, for: messageId) { existing in
            existing.task?.cancel()
            existing.service.cancelStream()
        }

        execution.task?.cancel()
        execution.task = Task { @MainActor in
            guard controller.sessionCoordinator.isSessionActive(session) else { return }
            let apiKey = self.resultApplier.activeAPIKey(for: session)

            do {
                let result = try await execution.service.fetchResponse(responseId: responseId, apiKey: apiKey)

                switch result.status {
                case .completed:
                    self.resultApplier.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.resultApplier.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.resultApplier.recoveryFallbackThinking(for: message, session: session)
                    )

                case .failed, .incomplete, .unknown:
                    if visible {
                        controller.errorMessage = result.errorMessage ?? "Response did not complete."
                    }
                    self.resultApplier.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.resultApplier.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.resultApplier.recoveryFallbackThinking(for: message, session: session)
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
                if self.resultApplier.handleUnrecoverableRecoveryError(
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
