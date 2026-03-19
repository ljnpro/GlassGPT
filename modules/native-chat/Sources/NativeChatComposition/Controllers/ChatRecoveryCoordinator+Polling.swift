import ChatPersistenceSwiftData
import ChatPersistenceCore
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func pollResponseUntilTerminal(session: ReplySession, responseId: String) async {
        let key = resultApplier.activeAPIKey(for: session)
        guard !key.isEmpty else { return }
        _ = await controller.sessionCoordinator.applyRuntimeTransition(.beginRecoveryPoll, to: session)
        controller.sessionCoordinator.syncVisibleState(from: session)
        var attempts = 0
        let maxAttempts = 180
        var lastResult: OpenAIResponseFetchResult?
        var lastError: String?

        while !Task.isCancelled && attempts < maxAttempts {
            attempts += 1

            do {
                guard let execution = controller.sessionRegistry.execution(for: session.messageID) else { return }
                let result = try await execution.service.fetchResponse(responseId: responseId, apiKey: key)
                lastResult = result

                switch result.status {
                case .queued, .inProgress:
                    #if DEBUG
                    if attempts <= 3 || attempts % 10 == 0 {
                        Loggers.recovery.debug("[Recovery] Response still \(result.status.rawValue), attempt \(attempts)/\(maxAttempts)")
                    }
                    #endif
                    do {
                        try await Task.sleep(nanoseconds: attempts < 10 ? 2_000_000_000 : 3_000_000_000)
                    } catch {
                        return
                    }

                case .completed, .incomplete, .failed, .unknown:
                    if let message = controller.conversationCoordinator.findMessage(byId: session.messageID) {
                        if result.status == .failed || result.status == .incomplete,
                           controller.visibleSessionMessageID == session.messageID {
                            controller.errorMessage = result.errorMessage ?? "Response did not complete."
                        }
                        resultApplier.finishRecovery(
                            for: message,
                            session: session,
                            result: result,
                            fallbackText: resultApplier.recoveryFallbackText(for: message, session: session),
                            fallbackThinking: resultApplier.recoveryFallbackThinking(for: message, session: session)
                        )
                    }
                    return
                }
            } catch {
                if let message = controller.conversationCoordinator.findMessage(byId: session.messageID),
                   resultApplier.handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: controller.visibleSessionMessageID == session.messageID
                   ) {
                    return
                }

                lastError = error.localizedDescription
                #if DEBUG
                Loggers.recovery.debug("[Recovery] Poll error: \(lastError ?? "unknown"), attempt \(attempts)/\(maxAttempts)")
                #endif

                do {
                    try await Task.sleep(nanoseconds: attempts < 10 ? 2_000_000_000 : 3_000_000_000)
                } catch {
                    return
                }
            }
        }

        guard !Task.isCancelled, let message = controller.conversationCoordinator.findMessage(byId: session.messageID) else { return }

        if controller.visibleSessionMessageID == session.messageID,
           let lastError,
           !lastError.isEmpty {
            controller.errorMessage = lastError
        }
        resultApplier.finishRecovery(
            for: message,
            session: session,
            result: lastResult,
            fallbackText: resultApplier.recoveryFallbackText(for: message, session: session),
            fallbackThinking: resultApplier.recoveryFallbackThinking(for: message, session: session)
        )

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Finished with fallback after \(attempts) attempts. Last error: \(lastError ?? "none")")
        #endif
    }

    func cancelBackgroundResponseAndSync(responseId: String, messageId: UUID) async {
        guard !controller.apiKey.isEmpty else { return }

        do {
            try await controller.openAIService.cancelResponse(responseId: responseId, apiKey: controller.apiKey)
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Background cancel failed for \(responseId): \(error.localizedDescription)")
            #endif
        }

        do {
            let result = try await controller.openAIService.fetchResponse(responseId: responseId, apiKey: controller.apiKey)

            switch result.status {
            case .queued, .inProgress:
                if let message = controller.conversationCoordinator.findMessage(byId: messageId),
                   let session = controller.sessionCoordinator.makeRecoverySession(for: message) {
                    controller.sessionCoordinator.registerSession(
                        session,
                        execution: SessionExecutionState(service: controller.serviceFactory()),
                        visible: false
                    )
                    await pollResponseUntilTerminal(session: session, responseId: responseId)
                }

            case .completed, .incomplete, .failed, .unknown:
                guard let message = controller.conversationCoordinator.findMessage(byId: messageId) else { return }
                resultApplier.applyRecoveredResult(
                    result,
                    to: message,
                    fallbackText: message.content,
                    fallbackThinking: message.thinking
                )
                controller.conversationCoordinator.saveContextIfPossible("cancelBackgroundResponseAndSync")
                controller.conversationCoordinator.upsertMessage(message)
                controller.fileInteractionCoordinator.prefetchGeneratedFilesIfNeeded(for: message)
            }
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Failed to refresh cancelled response \(responseId): \(error.localizedDescription)")
            #endif
        }
    }
}
