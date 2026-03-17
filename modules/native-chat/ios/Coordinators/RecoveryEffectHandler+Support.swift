import Foundation

@MainActor
extension RecoveryEffectHandler {
    func handleUnrecoverableRecoveryError(
        _ error: Error,
        for message: Message,
        responseId: String,
        session: ResponseSession,
        visible: Bool
    ) -> Bool {
        guard case let OpenAIServiceError.httpError(statusCode, responseBody) = error, statusCode == 404 else {
            return false
        }

        let fallbackText: String
        if message.usedBackgroundMode {
            if visible {
                viewModel.errorMessage = "This response is no longer resumable."
            }
            fallbackText = recoveryFallbackText(for: message, session: session)
        } else {
            if visible {
                viewModel.errorMessage = nil
            }
            fallbackText = interruptedResponseFallbackText(for: message, session: session)
        }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Response \(responseId) is no longer available: \(responseBody)")
        #endif

        finishRecovery(
            for: message,
            session: session,
            result: nil,
            fallbackText: fallbackText,
            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
        )
        return true
    }

    func recoveryFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        if let session, !session.currentText.isEmpty {
            return session.currentText
        }
        if message.id == viewModel.visibleSessionMessageID, !viewModel.currentStreamingText.isEmpty {
            return viewModel.currentStreamingText
        }
        return message.content
    }

    func recoveryFallbackThinking(for message: Message, session: ResponseSession? = nil) -> String? {
        if let session, !session.currentThinking.isEmpty {
            return session.currentThinking
        }
        if message.id == viewModel.visibleSessionMessageID, !viewModel.currentThinkingText.isEmpty {
            return viewModel.currentThinkingText
        }
        return message.thinking
    }

    func interruptedResponseFallbackText(for message: Message, session: ResponseSession? = nil) -> String {
        let interruptionNotice = "Response interrupted because the app was closed before completion."
        let baseText = recoveryFallbackText(for: message, session: session)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseText.isEmpty else {
            return interruptionNotice
        }

        if baseText.contains(interruptionNotice) {
            return baseText
        }

        return "\(baseText)\n\n\(interruptionNotice)"
    }

    func applyRecoveredResult(
        _ result: OpenAIResponseFetchResult?,
        to message: Message,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        viewModel.messagePersistence.applyRecoveredResult(
            result,
            to: message,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )
    }

    func finishRecovery(
        for message: Message,
        session: ResponseSession,
        result: OpenAIResponseFetchResult?,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        applyRecoveredResult(
            result,
            to: message,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )

        viewModel.saveContextIfPossible("finishRecovery")
        viewModel.upsertMessage(message)
        viewModel.prefetchGeneratedFilesIfNeeded(for: message)

        let conversation = message.conversation
        let wasVisible = viewModel.visibleSessionMessageID == session.messageID
        viewModel.removeSession(session)

        if let conversation {
            let viewModel = self.viewModel
            Task { @MainActor in
                await viewModel.generateTitleIfNeeded(for: conversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }
}
