import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
    func pollResponseUntilTerminal(session: ReplySession, responseId: String) async {
        let key = resultApplier.activeAPIKey(for: session)
        guard !key.isEmpty else { return }
        _ = await sessions.applyRuntimeTransition(.beginRecoveryPoll, to: session)
        sessions.syncVisibleState(from: session)
        var attempts = 0
        let maxAttempts = 180
        var lastResult: OpenAIResponseFetchResult?
        var lastError: String?

        while !Task.isCancelled, attempts < maxAttempts {
            attempts += 1

            do {
                guard let execution = services.sessionRegistry.execution(for: session.messageID) else { return }
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
                    if let message = conversations.findMessage(byId: session.messageID) {
                        if result.status == .failed || result.status == .incomplete,
                           sessions.visibleSessionMessageID == session.messageID {
                            state.errorMessage = result.errorMessage ?? "Response did not complete."
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
                if let message = conversations.findMessage(byId: session.messageID),
                   resultApplier.handleUnrecoverableRecoveryError(
                       error,
                       for: message,
                       responseId: responseId,
                       session: session,
                       visible: sessions.visibleSessionMessageID == session.messageID
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

        guard !Task.isCancelled, let message = conversations.findMessage(byId: session.messageID) else { return }

        if sessions.visibleSessionMessageID == session.messageID,
           let lastError,
           !lastError.isEmpty {
            state.errorMessage = lastError
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
        let apiKey = services.apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else { return }

        do {
            try await services.openAIService.cancelResponse(responseId: responseId, apiKey: apiKey)
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Background cancel failed for \(responseId): \(error.localizedDescription)")
            #endif
        }

        do {
            let result = try await services.openAIService.fetchResponse(responseId: responseId, apiKey: apiKey)

            switch result.status {
            case .queued, .inProgress:
                if let message = conversations.findMessage(byId: messageId),
                   let session = sessions.makeRecoverySession(for: message) {
                    sessions.registerSession(
                        session,
                        execution: SessionExecutionState(service: services.serviceFactory()),
                        visible: false
                    )
                    await pollResponseUntilTerminal(session: session, responseId: responseId)
                }

            case .completed, .incomplete, .failed, .unknown:
                guard let message = conversations.findMessage(byId: messageId) else { return }
                resultApplier.applyRecoveredResult(
                    result,
                    to: message,
                    fallbackText: message.content,
                    fallbackThinking: message.thinking
                )
                conversations.saveContextIfPossible("cancelBackgroundResponseAndSync")
                conversations.upsertMessage(message)
                files.prefetchGeneratedFilesIfNeeded(for: message)
            }
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Failed to refresh cancelled response \(responseId): \(error.localizedDescription)")
            #endif
        }
    }
}
