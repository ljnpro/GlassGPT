import Foundation

@MainActor
extension RecoveryEffectHandler {
    func pollResponseUntilTerminal(session: ResponseSession, responseId: String) async {
        let viewModel = self.viewModel
        let key = activeAPIKey(for: session)
        guard !key.isEmpty else { return }
        session.beginRecoveryPoll()
        viewModel.setRecoveryPhase(.pollingTerminal, for: session)
        var attempts = 0
        let maxAttempts = 180
        var lastResult: OpenAIResponseFetchResult?
        var lastError: String?

        while !Task.isCancelled && attempts < maxAttempts {
            attempts += 1

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: key)
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
                    if let message = viewModel.findMessage(byId: session.messageID) {
                        if result.status == .failed || result.status == .incomplete,
                           viewModel.visibleSessionMessageID == session.messageID {
                            viewModel.errorMessage = result.errorMessage ?? "Response did not complete."
                        }
                        finishRecovery(
                            for: message,
                            session: session,
                            result: result,
                            fallbackText: recoveryFallbackText(for: message, session: session),
                            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
                        )
                    }
                    return
                }
            } catch {
                if let message = viewModel.findMessage(byId: session.messageID),
                   handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: viewModel.visibleSessionMessageID == session.messageID
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

        guard !Task.isCancelled, let message = viewModel.findMessage(byId: session.messageID) else { return }

        if viewModel.visibleSessionMessageID == session.messageID,
           let lastError,
           !lastError.isEmpty {
            viewModel.errorMessage = lastError
        }
        finishRecovery(
            for: message,
            session: session,
            result: lastResult,
            fallbackText: recoveryFallbackText(for: message, session: session),
            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
        )

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Finished with fallback after \(attempts) attempts. Last error: \(lastError ?? "none")")
        #endif
    }

    func cancelBackgroundResponseAndSync(responseId: String, messageId: UUID) async {
        let viewModel = self.viewModel
        guard !viewModel.apiKey.isEmpty else { return }

        do {
            try await viewModel.openAIService.cancelResponse(responseId: responseId, apiKey: viewModel.apiKey)
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Background cancel failed for \(responseId): \(error.localizedDescription)")
            #endif
        }

        do {
            let result = try await viewModel.openAIService.fetchResponse(responseId: responseId, apiKey: viewModel.apiKey)

            switch result.status {
            case .queued, .inProgress:
                if let message = viewModel.findMessage(byId: messageId),
                   let session = viewModel.makeRecoverySession(for: message) {
                    viewModel.registerSession(session, visible: false)
                    await pollResponseUntilTerminal(session: session, responseId: responseId)
                }

            case .completed, .incomplete, .failed, .unknown:
                guard let message = viewModel.findMessage(byId: messageId) else { return }
                applyRecoveredResult(
                    result,
                    to: message,
                    fallbackText: message.content,
                    fallbackThinking: message.thinking
                )
                viewModel.saveContextIfPossible("cancelBackgroundResponseAndSync")
                viewModel.upsertMessage(message)
                viewModel.prefetchGeneratedFilesIfNeeded(for: message)
            }
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Stop] Failed to refresh cancelled response \(responseId): \(error.localizedDescription)")
            #endif
        }
    }
}
