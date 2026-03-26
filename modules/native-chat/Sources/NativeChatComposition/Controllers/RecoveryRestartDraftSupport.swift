import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
extension ChatRecoveryCoordinator {
    func prepareRestartedRecoveryReply(
        for message: Message,
        visible: Bool
    ) -> PreparedAssistantReply? {
        do {
            var preparedReply = try drafts.prepareExistingDraft(message)
            preparedReply.assistantReplyID = AssistantReplyID()
            return preparedReply
        } catch SendMessagePreparationError.missingAPIKey {
            if visible {
                state.errorMessage = "Please add your OpenAI API key in Settings."
            }
            return nil
        } catch {
            if visible {
                state.errorMessage = "Failed to restart the interrupted response."
            }
            Loggers.recovery.error("[Recovery] Failed to prepare restarted draft: \(error.localizedDescription)")
            return nil
        }
    }

    func resetDraftForRestart(
        _ message: Message,
        preparedReply: PreparedAssistantReply
    ) {
        message.content = ""
        message.thinking = nil
        message.toolCalls = []
        message.annotations = []
        message.filePathAnnotations = []
        message.lastSequenceNumber = nil
        message.responseId = nil
        message.isComplete = false
        message.usedBackgroundMode = preparedReply.requestUsesBackgroundMode
    }
}
