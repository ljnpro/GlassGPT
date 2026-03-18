import ChatPersistenceSwiftData
import ChatPersistenceCore
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatController {
    @discardableResult
    func handleUnrecoverableRecoveryError(
        _ error: Error,
        for message: Message,
        responseId: String,
        session: ReplySession,
        visible: Bool
    ) -> Bool {
        guard case let OpenAIServiceError.httpError(statusCode, responseBody) = error, statusCode == 404 else {
            return false
        }

        let fallbackText: String
        if message.usedBackgroundMode {
            if visible {
                errorMessage = "This response is no longer resumable."
            }
            fallbackText = recoveryFallbackText(for: message, session: session)
        } else {
            if visible {
                errorMessage = nil
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

    func recoveryFallbackText(for message: Message, session: ReplySession? = nil) -> String {
        if let session, !session.currentText.isEmpty {
            return session.currentText
        }
        if message.id == visibleSessionMessageID, !currentStreamingText.isEmpty {
            return currentStreamingText
        }
        return message.content
    }

    func recoveryFallbackThinking(for message: Message, session: ReplySession? = nil) -> String? {
        if let session, !session.currentThinking.isEmpty {
            return session.currentThinking
        }
        if message.id == visibleSessionMessageID, !currentThinkingText.isEmpty {
            return currentThinkingText
        }
        return message.thinking
    }

    func interruptedResponseFallbackText(for message: Message, session: ReplySession? = nil) -> String {
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

    func activeAPIKey(for session: ReplySession) -> String {
        let key = session.request.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? apiKey : key
    }

    func applyRecoveredResult(
        _ result: OpenAIResponseFetchResult?,
        to message: Message,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        messagePersistence.applyRecoveredResult(
            result,
            to: message,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )
    }

    func finishRecovery(
        for message: Message,
        session: ReplySession,
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

        saveContextIfPossible("finishRecovery")
        upsertMessage(message)
        prefetchGeneratedFilesIfNeeded(for: message)

        let conversation = message.conversation
        let wasVisible = visibleSessionMessageID == session.messageID
        removeSession(session)

        if let conversation {
            let viewModel = self
            Task { @MainActor in
                await viewModel.generateTitleIfNeeded(for: conversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }
}
