import ChatPersistenceSwiftData
import ChatPersistenceCore
import ChatUIComponents
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
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
                controller.errorMessage = "This response is no longer resumable."
            }
            fallbackText = recoveryFallbackText(for: message, session: session)
        } else {
            if visible {
                controller.errorMessage = nil
            }
            fallbackText = interruptedResponseFallbackText(for: message, session: session)
        }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Response \(responseId) is no longer available: \(responseBody)")
        #endif

        controller.finishRecovery(
            for: message,
            session: session,
            result: nil,
            fallbackText: fallbackText,
            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
        )
        return true
    }

    func recoveryFallbackText(for message: Message, session: ReplySession? = nil) -> String {
        if let session,
           let runtimeState = controller.cachedRuntimeState(for: session),
           !runtimeState.buffer.text.isEmpty {
            return runtimeState.buffer.text
        }
        if message.id == controller.visibleSessionMessageID, !controller.currentStreamingText.isEmpty {
            return controller.currentStreamingText
        }
        return message.content
    }

    func recoveryFallbackThinking(for message: Message, session: ReplySession? = nil) -> String? {
        if let session,
           let runtimeState = controller.cachedRuntimeState(for: session),
           !runtimeState.buffer.thinking.isEmpty {
            return runtimeState.buffer.thinking
        }
        if message.id == controller.visibleSessionMessageID, !controller.currentThinkingText.isEmpty {
            return controller.currentThinkingText
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
        return key.isEmpty ? controller.apiKey : key
    }

    func applyRecoveredResult(
        _ result: OpenAIResponseFetchResult?,
        to message: Message,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        controller.messagePersistence.applyRecoveredResult(
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

        controller.saveContextIfPossible("finishRecovery")
        controller.upsertMessage(message)
        controller.prefetchGeneratedFilesIfNeeded(for: message)

        let conversation = message.conversation
        let wasVisible = controller.visibleSessionMessageID == session.messageID
        controller.removeSession(session)

        if let conversation {
            let viewModel = controller
            Task { @MainActor in
                await viewModel.generateTitleIfNeeded(for: conversation)
            }
        }

        if wasVisible {
            HapticService.shared.notify(.success)
        }
    }
}
