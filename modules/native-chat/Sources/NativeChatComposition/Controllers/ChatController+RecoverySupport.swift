import ChatPersistenceSwiftData
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
        recoveryCoordinator.handleUnrecoverableRecoveryError(
            error,
            for: message,
            responseId: responseId,
            session: session,
            visible: visible
        )
    }

    func recoveryFallbackText(for message: Message, session: ReplySession? = nil) -> String {
        recoveryCoordinator.recoveryFallbackText(for: message, session: session)
    }

    func recoveryFallbackThinking(for message: Message, session: ReplySession? = nil) -> String? {
        recoveryCoordinator.recoveryFallbackThinking(for: message, session: session)
    }

    func interruptedResponseFallbackText(for message: Message, session: ReplySession? = nil) -> String {
        recoveryCoordinator.interruptedResponseFallbackText(for: message, session: session)
    }

    func activeAPIKey(for session: ReplySession) -> String {
        recoveryCoordinator.activeAPIKey(for: session)
    }

    func applyRecoveredResult(
        _ result: OpenAIResponseFetchResult?,
        to message: Message,
        fallbackText: String,
        fallbackThinking: String?
    ) {
        recoveryCoordinator.applyRecoveredResult(
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
        recoveryCoordinator.finishRecovery(
            for: message,
            session: session,
            result: result,
            fallbackText: fallbackText,
            fallbackThinking: fallbackThinking
        )
    }
}
